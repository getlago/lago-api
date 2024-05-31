# frozen_string_literal: true

module V1
  module Legacy
    class ChargeSerializer < ModelSerializer
      def serialize
        ::CollectionSerializer.new(
          model.group_properties,
          ::V1::Legacy::GroupPropertiesSerializer,
          collection_name: 'group_properties'
        ).serialize
      end
    end
  end
end
