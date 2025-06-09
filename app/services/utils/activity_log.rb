# frozen_string_literal: true

module Utils
  class ActivityLog
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

    def self.produce(*, **, &)
      new(*, **, &).produce
    end

    def initialize(object, activity_type, activity_id: SecureRandom.uuid, &block)
      @object = object
      @activity_type = activity_type
      @activity_id = activity_id
      @block = block
    end

    def produce
      return block.call if object.nil? && block

      changes = {}
      if block
        before_attrs = object_serialized
        result = block.call
        return result if result.failure?

        object.reload
        after_attrs = object_serialized

        changes = before_attrs.each_with_object({}) do |(key, before), result|
          after = after_attrs[key]
          result[key] = [before, after] if before != after
        end
      end

      produce_with_diff(changes)
      block ? result : nil
    end

    private

    attr_reader :object, :activity_type, :activity_id, :block

    def produce_with_diff(changes)
      return if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return if ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"].blank?

      current_time = Time.current.iso8601[...-1]
      Karafka.producer.produce_async(
        topic: ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"],
        key: "#{organization_id}--#{activity_id}",
        payload: {
          activity_source:,
          api_key_id: CurrentContext.api_key_id,
          user_id: user_id,
          activity_type:,
          activity_id:,
          logged_at: current_time,
          created_at: current_time,
          resource_id: resource.id,
          resource_type: resource.class.name,
          organization_id: organization_id,
          activity_object: object_serialized,
          activity_object_changes: object_changes(changes),
          external_customer_id: external_customer_id,
          external_subscription_id: external_subscription_id
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

      Membership.find_by(organization_id:, id: CurrentContext.membership.split("/").last)&.user_id
    end

    def object_serialized
      serializer = "V1::#{object.class.name}Serializer".constantize
      root_name = object.class.name.underscore.to_sym

      serializer.new(object, root_name:, includes: SERIALIZED_INCLUDED_OBJECTS[root_name] || []).serialize
    end

    def object_changes(changes)
      return {} unless activity_type.include?("updated")

      changes.except(*IGNORED_FIELDS)
    end

    def organization_id
      case object.class.name
      when "AppliedCoupon"
        object.coupon.organization_id
      else
        object.organization_id
      end
    end

    def resource
      case object.class.name
      when "Payment"
        object.payable
      when "PaymentReceipt"
        object.payment.payable
      when "AppliedCoupon"
        object.coupon
      when "WalletTransaction"
        object.wallet
      else
        object
      end
    end

    def external_customer_id
      return nil if IGNORED_EXTERNAL_CUSTOMER_ID_CLASSES.include?(object.class.name)
      return object.external_id if object.is_a?(Customer)

      object.customer&.external_id
    end

    def external_subscription_id
      return nil unless object.is_a?(Subscription)

      object.external_id
    end
  end
end
