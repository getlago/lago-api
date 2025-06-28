# frozen_string_literal: true

module V1
  class PlanEntitlementsSerializer < ModelSerializer
    def serialize
      {
        code: model.feature.code,
        name: model.feature.name,
        description: model.feature.description,
        privileges: model.values.map do |p|
          {
            code: p.privilege.code,
            name: p.privilege.name,
            value_type: p.privilege.value_type,
            value: cast_value(p.value, p.privilege.value_type),
            config: p.privilege.config
          }
        end.index_by { |p| p[:code] }
      }
    end

    private

    # TODO: Remove this duplication from SubscriptionEntitlement
    def cast_value(raw_value, type)
      return nil if raw_value.nil?

      case type
      when "integer"
        raw_value.to_i
      when "boolean"
        ActiveModel::Type::Boolean.new.cast(raw_value)
      else
        raw_value.to_s
      end
    end
  end
end
