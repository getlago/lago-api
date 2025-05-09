# frozen_string_literal: true

module Utils
  class ActivityLog
    class << self
      IGNORED_FIELDS = %w[updated_at].freeze

      def produce(object, activity_type, activity_id: SecureRandom.uuid)
        before_attrs = object_serialized(object)
        result = yield
        after_attrs = object_serialized(object.reload)

        changes = before_attrs.each_with_object({}) do |(key, before), result|
          after = after_attrs[key]
          result[key] = [before, after] if before != after
        end

        produce_with_diff(object, activity_type, object_changes: changes, activity_id:)
        result
      end

      private

      def produce_with_diff(object, activity_type, object_changes: {}, activity_id:)
        return if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
        return if ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"].blank?

        current_time = Time.current.iso8601[...-1]
        Karafka.producer.produce_async(
          topic: ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"],
          key: "#{organization_id(object)}--#{activity_id}",
          payload: {
            activity_source:,
            api_key_id: CurrentContext.api_key_id,
            user_id:,
            activity_type:,
            activity_id:,
            logged_at: current_time,
            created_at: current_time,
            resource_id: resource(object).id,
            resource_type: resource(object).class.name,
            organization_id: organization_id(object),
            activity_object: activity_object(object, activity_type),
            activity_object_changes: activity_object_changes(object_changes, activity_type)
          }.to_json
        )
      end

      def activity_source
        return "front" if CurrentContext.source == "graphql"

        CurrentContext.source || "system"
      end

      def user_id
        return nil if CurrentContext.api_key_id.present?
        return nil if CurrentContext.membership.blank?

        Membership.find_by(id: CurrentContext.membership.split("/").last)&.user_id
      end

      def activity_object(object, activity_type)
        return {} if activity_type.include?("deleted")

        object_serialized(object)
      end

      def object_serialized(object)
        "V1::#{object.class.name}Serializer".constantize.new(object).serialize
      end

      def activity_object_changes(object_changes, activity_type)
        return {} if activity_type.include?("deleted")
        return {} if object_changes.key?("id")

        object_changes.transform_values(&:to_s)
      end

      def organization_id(activity_object)
        case activity_object.class.name
        when "AppliedCoupon"
          activity_object.coupon.organization_id
        else
          activity_object.organization_id
        end
      end

      def resource(activity_object)
        case activity_object.class.name
        when "Payment"
          activity_object.invoice
        when "AppliedCoupon"
          activity_object.coupon
        when "WalletTransaction"
          activity_object.wallet
        else
          activity_object
        end
      end
    end
  end
end
