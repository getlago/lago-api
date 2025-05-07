# frozen_string_literal: true

module Utils
  class ActivityLog
    class << self
      IGNORED_FIELDS = %w[updated_at].freeze

      def produce(object, activity_type, activity_id: SecureRandom.uuid)
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
            activity_object_changes: activity_object_changes(object, activity_type)
          }.to_json
        )
      end

      private

      def activity_source
        return "front" if CurrentContext.source == "graphql"

        CurrentContext.source
      end

      def user_id
        return nil if CurrentContext.api_key_id.present?
        return nil if CurrentContext.membership.blank?

        Membership.find_by(id: CurrentContext.membership.split("/").last)&.user_id
      end

      def activity_object(object, activity_type)
        return nil if activity_type.include?("deleted")

        "V1::#{object.class.name}Serializer".constantize.new(object).serialize
      end

      # TODO: Fetch previous changes for associated objects (e.g. billable_metric.filters)
      def activity_object_changes(object, activity_type)
        return nil if activity_type.include?("deleted")

        changes = object.previous_changes.except(*IGNORED_FIELDS).transform_values(&:to_s)

        return nil if changes.key?("id")

        changes
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
