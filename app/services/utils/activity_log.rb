# frozen_string_literal: true

module Utils
  class ActivityLog
    class << self
      IGNORED_FIELDS = %i[updated_at].freeze
      IGNORED_EXTERNAL_CUSTOMER_ID_CLASSES = %w[BillableMetric Coupon Plan BillingEntity].freeze
      SERIALIZED_INCLUDED_OBJECTS = {
        billing_entity: %i[taxes],
        credit_note: %i[items applied_taxes error_details],
        customer: %i[taxes integration_customers applicable_invoice_custom_sections],
        invoice: %i[customer integration_customers billing_periods subscriptions fees credits metadata applied_taxes error_details applied_invoice_custom_sections],
        plan: %i[charges usage_thresholds taxes minimum_commitment],
        subscription: %i[plan],
        wallet: %i[recurring_transaction_rules]
      }.freeze

      def produce(object, activity_type, activity_id: SecureRandom.uuid, changes: nil)
        return yield if object.nil? && block_given?

        if block_given?
          before_attrs = object_serialized(object)
          result = yield
          return result if result.failure?

          after_attrs = object_serialized(object.reload)

          changes = before_attrs.each_with_object({}) do |(key, before), result|
            after = after_attrs[key]
            result[key] = [before, after] if before != after
          end
        end

        produce_with_diff(object, activity_type, activity_id:, object_changes: changes)
        block_given? ? result : nil
      end

      private

      def produce_with_diff(object, activity_type, activity_id:, object_changes: {})
        return if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
        return if ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"].blank?

        current_time = Time.current.iso8601[...-1]
        Karafka.producer.produce_async(
          topic: ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"],
          key: "#{organization_id(object)}--#{activity_id}",
          payload: {
            activity_source:,
            api_key_id: CurrentContext.api_key_id,
            user_id: user_id(object),
            activity_type:,
            activity_id:,
            logged_at: current_time,
            created_at: current_time,
            resource_id: resource(object).id,
            resource_type: resource(object).class.name,
            organization_id: organization_id(object),
            activity_object: activity_object(object, activity_type),
            activity_object_changes: activity_object_changes(object_changes, activity_type),
            external_customer_id: external_customer_id(object),
            external_subscription_id: external_subscription_id(object)
          }.to_json
        )
      end

      def activity_source
        return "front" if CurrentContext.source == "graphql"

        CurrentContext.source || "system"
      end

      def user_id(object)
        return nil if CurrentContext.api_key_id.present?
        return nil if CurrentContext.membership.blank?

        Membership.find_by(
          organization_id: organization_id(object),
          id: CurrentContext.membership.split("/").last
        )&.user_id
      end

      def activity_object(object, activity_type)
        object_serialized(object)
      end

      def object_serialized(object)
        serializer = "V1::#{object.class.name}Serializer".constantize
        root_name = object.class.name.underscore.to_sym

        serializer.new(object, root_name:, includes: SERIALIZED_INCLUDED_OBJECTS[root_name] || []).serialize
      end

      def activity_object_changes(object_changes, activity_type)
        return {} unless activity_type.include?("updated")

        object_changes&.except(*IGNORED_FIELDS)
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
          activity_object.payable
        when "PaymentReceipt"
          activity_object.payment.payable
        when "AppliedCoupon"
          activity_object.coupon
        when "WalletTransaction"
          activity_object.wallet
        else
          activity_object
        end
      end

      def external_customer_id(activity_object)
        return nil if IGNORED_EXTERNAL_CUSTOMER_ID_CLASSES.include?(activity_object.class.name)
        return activity_object.external_id if activity_object.is_a?(Customer)

        activity_object.customer&.external_id
      end

      def external_subscription_id(activity_object)
        return nil unless activity_object.is_a?(Subscription)

        activity_object.external_id
      end
    end
  end
end
