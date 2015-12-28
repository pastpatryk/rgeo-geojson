module RGeo
  module GeoJSON
    # This object encapsulates encoding and decoding settings (principally
    # the RGeo::Feature::Factory and the RGeo::GeoJSON::EntityFactory to
    # be used) so that you can encode and decode without specifying those
    # settings every time.

    class Coder
      # Create a new coder settings object. The geo factory is passed as
      # a required argument.
      #
      # Options include:
      #
      # [<tt>:geo_factory</tt>]
      #   Specifies the geo factory to use to create geometry objects.
      #   Defaults to the preferred cartesian factory.
      # [<tt>:entity_factory</tt>]
      #   Specifies an entity factory, which lets you override the types
      #   of GeoJSON entities that are created. It defaults to the default
      #   RGeo::GeoJSON::EntityFactory, which generates objects of type
      #   RGeo::GeoJSON::Feature or RGeo::GeoJSON::FeatureCollection.
      #   See RGeo::GeoJSON::EntityFactory for more information.
      # [<tt>:json_parser</tt>]
      #   Specifies a JSON parser to use when decoding a String or IO
      #   object. The value may be a Proc object taking the string as the
      #   sole argument and returning the JSON hash, or it may be one of
      #   the special values <tt>:json</tt>, <tt>:yajl</tt>, or
      #   <tt>:active_support</tt>. Setting one of those special values
      #   will require the corresponding library to be available. Note
      #   that the <tt>:json</tt> library is present in the standard
      #   library in Ruby 1.9.
      #   If a parser is not specified, then the decode method will not
      #   accept a String or IO object; it will require a Hash.

      def initialize(opts_ = {})
        @geo_factory = opts_[:geo_factory] || ::RGeo::Cartesian.preferred_factory
        @entity_factory = opts_[:entity_factory] || EntityFactory.instance
        @json_parser = opts_[:json_parser]
        case @json_parser
        when :json
          require "json" unless defined?(JSON)
          @json_parser = Proc.new { |str_| JSON.parse(str_) }
        when :yajl
          require "yajl" unless defined?(Yajl)
          @json_parser = Proc.new { |str_| Yajl::Parser.new.parse(str_) }
        when :active_support
          require "active_support/json" unless defined?(ActiveSupport::JSON)
          @json_parser = Proc.new { |str_| ActiveSupport::JSON.decode(str_) }
        when Proc, nil
          # Leave as is
        else
          raise ::ArgumentError, "Unrecognzied json_parser: #{@json_parser.inspect}"
        end
        @num_coordinates = 2
        @num_coordinates += 1 if @geo_factory.property(:has_z_coordinate)
        @num_coordinates += 1 if @geo_factory.property(:has_m_coordinate)
      end

      # Encode the given object as GeoJSON. The object may be one of the
      # geometry objects specified in RGeo::Feature, or an appropriate
      # GeoJSON wrapper entity supported by this coder's entity factory.
      #
      # This method returns a JSON object (i.e. a hash). In order to
      # generate a string suitable for transmitting to a service, you
      # will need to JSON-encode it. This is usually accomplished by
      # calling <tt>to_json</tt> on the hash object, if you have the
      # appropriate JSON library installed.
      #
      # Returns nil if nil is passed in as the object.

      def encode(object_)
        if @entity_factory.is_feature_collection?(object_)
          {
            "type" => "FeatureCollection",
            "features" => @entity_factory.map_feature_collection(object_) { |f_| _encode_feature(f_) },
          }
        elsif @entity_factory.is_feature?(object_)
          _encode_feature(object_)
        elsif object_.nil?
          nil
        else
          _encode_geometry(object_)
        end
      end

      # Decode an object from GeoJSON. The input may be a JSON hash, a
      # String, or an IO object from which to read the JSON string.
      # If an error occurs, nil is returned.

      def decode(input_)
        if input_.is_a?(::IO)
          input_ = input_.read rescue nil
        end
        if input_.is_a?(::String)
          input_ = @json_parser.call(input_) rescue nil
        end
        unless input_.is_a?(::Hash)
          return nil
        end
        case input_["type"]
        when "FeatureCollection"
          features_ = input_["features"]
          features_ = [] unless features_.is_a?(::Array)
          decoded_features_ = []
          features_.each do |f_|
            if f_["type"] == "Feature"
              decoded_features_ << _decode_feature(f_)
            end
          end
          @entity_factory.feature_collection(decoded_features_)
        when "Feature"
          _decode_feature(input_)
        else
          _decode_geometry(input_)
        end
      end

      # Returns the RGeo::Feature::Factory used to generate geometry objects.

      attr_reader :geo_factory

      # Returns the RGeo::GeoJSON::EntityFactory used to generate GeoJSON
      # wrapper entities.

      attr_reader :entity_factory

      def _encode_feature(object_) # :nodoc:
        json_ = {
          "type" => "Feature",
          "geometry" => _encode_geometry(@entity_factory.get_feature_geometry(object_)),
          "properties" => @entity_factory.get_feature_properties(object_).dup,
        }
        id_ = @entity_factory.get_feature_id(object_)
        json_["id"] = id_ if id_
        json_
      end

      def _encode_geometry(object_, point_encoder_ = nil) # :nodoc:
        unless point_encoder_
          if object_.factory.property(:has_z_coordinate)
            if object_.factory.property(:has_m_coordinate)
              point_encoder_ = ::Proc.new { |p_| [p_.x, p_.y, p_.z, p_.m] }
            else
              point_encoder_ = ::Proc.new { |p_| [p_.x, p_.y, p_.z] }
            end
          else
            if object_.factory.property(:has_m_coordinate)
              point_encoder_ = ::Proc.new { |p_| [p_.x, p_.y, p_.m] }
            else
              point_encoder_ = ::Proc.new { |p_| [p_.x, p_.y] }
            end
          end
        end
        case object_
        when ::RGeo::Feature::Point
          {
            "type" => "Point",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::LineString
          {
            "type" => "LineString",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::Polygon
          {
            "type" => "Polygon",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::MultiPoint
          {
            "type" => "MultiPoint",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::MultiLineString
          {
            "type" => "MultiLineString",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::MultiPolygon
          {
            "type" => "MultiPolygon",
            "coordinates" => object_.coordinates
          }
        when ::RGeo::Feature::GeometryCollection
          {
            "type" => "GeometryCollection",
            "geometries" => object_.map { |geom_| _encode_geometry(geom_, point_encoder_) },
          }
        else
          nil
        end
      end

      def _decode_feature(input_) # :nodoc:
        geometry_ = input_["geometry"]
        if geometry_
          geometry_ = _decode_geometry(geometry_)
          return nil unless geometry_
        end
        @entity_factory.feature(geometry_, input_["id"], input_["properties"])
      end

      def _decode_geometry(input_) # :nodoc:
        case input_["type"]
        when "GeometryCollection"
          _decode_geometry_collection(input_)
        when "Point"
          _decode_point_coords(input_["coordinates"])
        when "LineString"
          _decode_line_string_coords(input_["coordinates"])
        when "Polygon"
          _decode_polygon_coords(input_["coordinates"])
        when "MultiPoint"
          _decode_multi_point_coords(input_["coordinates"])
        when "MultiLineString"
          _decode_multi_line_string_coords(input_["coordinates"])
        when "MultiPolygon"
          _decode_multi_polygon_coords(input_["coordinates"])
        else
          nil
        end
      end

      def _decode_geometry_collection(input_)  # :nodoc:
        geometries_ = input_["geometries"]
        geometries_ = [] unless geometries_.is_a?(::Array)
        decoded_geometries_ = []
        geometries_.each do |g_|
          g_ = _decode_geometry(g_)
          decoded_geometries_ << g_ if g_
        end
        @geo_factory.collection(decoded_geometries_)
      end

      def _decode_point_coords(point_coords_)  # :nodoc:
        return nil unless point_coords_.is_a?(::Array)
        @geo_factory.point(*(point_coords_[0...@num_coordinates].map(&:to_f))) rescue nil
      end

      def _decode_line_string_coords(line_coords_) # :nodoc:
        return nil unless line_coords_.is_a?(::Array)
        points_ = []
        line_coords_.each do |point_coords_|
          point_ = _decode_point_coords(point_coords_)
          points_ << point_ if point_
        end
        @geo_factory.line_string(points_)
      end

      def _decode_polygon_coords(poly_coords_) # :nodoc:
        return nil unless poly_coords_.is_a?(::Array)
        rings_ = []
        poly_coords_.each do |ring_coords_|
          return nil unless ring_coords_.is_a?(::Array)
          points_ = []
          ring_coords_.each do |point_coords_|
            point_ = _decode_point_coords(point_coords_)
            points_ << point_ if point_
          end
          ring_ = @geo_factory.linear_ring(points_)
          rings_ << ring_ if ring_
        end
        if rings_.size == 0
          nil
        else
          @geo_factory.polygon(rings_[0], rings_[1..-1])
        end
      end

      def _decode_multi_point_coords(multi_point_coords_) # :nodoc:
        return nil unless multi_point_coords_.is_a?(::Array)
        points_ = []
        multi_point_coords_.each do |point_coords_|
          point_ = _decode_point_coords(point_coords_)
          points_ << point_ if point_
        end
        @geo_factory.multi_point(points_)
      end

      def _decode_multi_line_string_coords(multi_line_coords_) # :nodoc:
        return nil unless multi_line_coords_.is_a?(::Array)
        lines_ = []
        multi_line_coords_.each do |line_coords_|
          line_ = _decode_line_string_coords(line_coords_)
          lines_ << line_ if line_
        end
        @geo_factory.multi_line_string(lines_)
      end

      def _decode_multi_polygon_coords(multi_polygon_coords_) # :nodoc:
        return nil unless multi_polygon_coords_.is_a?(::Array)
        polygons_ = []
        multi_polygon_coords_.each do |poly_coords_|
          poly_ = _decode_polygon_coords(poly_coords_)
          polygons_ << poly_ if poly_
        end
        @geo_factory.multi_polygon(polygons_)
      end
    end
  end
end
