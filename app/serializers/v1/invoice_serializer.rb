# frozen_string_literal: true

module V1
  class InvoiceSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        billing_entity_code: model.billing_entity.code,
        sequential_id: model.sequential_id,
        number: model.number,
        issuing_date: model.issuing_date&.iso8601,
        payment_due_date: model.payment_due_date&.iso8601,
        net_payment_term: model.net_payment_term,
        invoice_type: model.invoice_type,
        status: model.status,
        payment_status: model.payment_status,
        payment_dispute_lost_at: model.payment_dispute_lost_at,
        payment_overdue: model.payment_overdue,
        currency: model.currency,
        fees_amount_cents: model.fees_amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        progressive_billing_credit_amount_cents: model.progressive_billing_credit_amount_cents,
        coupons_amount_cents: model.coupons_amount_cents,
        credit_notes_amount_cents: model.credit_notes_amount_cents,
        sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents,
        sub_total_including_taxes_amount_cents: model.sub_total_including_taxes_amount_cents,
        total_amount_cents: model.total_amount_cents,
        total_due_amount_cents: model.total_due_amount_cents,
        prepaid_credit_amount_cents: model.prepaid_credit_amount_cents,
        file_url: model.file_url,
        version_number: model.version_number,
        self_billed: model.self_billed,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        voided_at: model.voided_at&.iso8601
      }

      payload.merge!(customer) if include?(:customer)
      payload.merge!(subscriptions) if include?(:subscriptions)
      payload.merge!(billing_periods) if include?(:billing_periods)
      payload.merge!(fees) if include?(:fees)
      payload.merge!(credits) if include?(:credits)
      payload.merge!(metadata) if include?(:metadata)
      payload.merge!(applied_taxes) if include?(:applied_taxes)
      payload.merge!(error_details) if include?(:error_details)
      payload.merge!(applied_usage_thresholds) if model.progressive_billing?
      payload.merge!(applied_invoice_custom_sections) if include?(:applied_invoice_custom_sections)
      payload.merge!(preview_subscriptions) if include?(:preview_subscriptions)
      payload.merge!(preview_fees) if include?(:preview_fees)

      payload
    end

    private

    def customer
      { customer: customer_data }

    end

    def customer_data
      if model.finalized? && model.customer_name.present?
        build_snapshotted_customer_data
      else
        ::V1::CustomerSerializer.new(
          model.customer,
          includes: include?(:integration_customers) ? [:integration_customers] : []
        ).serialize
      end
    end

    def build_snapshotted_customer_data
      billing_address = model.billing_address

      {
        lago_id: model.customer.id,
        billing_entity_code: model.customer.billing_entity.code,
        external_id: model.customer.external_id,
        account_type: model.customer.account_type,
        name: model.customer_name,
        firstname: model.customer_firstname,
        lastname: model.customer_lastname,
        customer_type: model.customer.customer_type,
        sequential_id: model.customer.sequential_id,
        slug: model.customer.slug,
        created_at: model.customer.created_at.iso8601,
        updated_at: model.customer.updated_at.iso8601,
        country: billing_address[:country],
        address_line1: billing_address[:address_line1],
        address_line2: billing_address[:address_line2],
        state: billing_address[:state],
        zipcode: billing_address[:zipcode],
        email: model.customer_email,
        city: billing_address[:city],
        url: model.customer_url,
        phone: model.customer_phone,
        logo_url: model.customer.logo_url,
        legal_name: model.customer_legal_name,
        legal_number: model.customer_legal_number,
        currency: model.customer.currency,
        tax_identification_number: model.customer_tax_identification_number,
        timezone: model.customer_timezone,
        applicable_timezone: model.customer.applicable_timezone,
        net_payment_term: model.customer.net_payment_term,
        external_salesforce_id: model.customer.external_salesforce_id,
        finalize_zero_amount_invoice: model.customer.finalize_zero_amount_invoice,
        billing_configuration: build_billing_configuration,
        shipping_address: model.customer.shipping_address_ancor,
        skip_invoice_custom_sections: model.customer.skip_invoice_custom_sections,
        metadata: build_customer_metadata
      }
    end

    def build_billing_configuration
      configuration = {
        invoice_grace_period: model.customer.invoice_grace_period,
        payment_provider: model.customer.payment_provider,
        payment_provider_code: model.customer.payment_provider_code,
        document_locale: model.customer.document_locale
      }

      case model.customer.payment_provider&.to_sym
      when :stripe
        configuration[:provider_customer_id] = model.customer.stripe_customer&.provider_customer_id
        configuration[:provider_payment_methods] = model.customer.stripe_customer&.provider_payment_methods
        configuration.merge!(model.customer.stripe_customer&.settings&.symbolize_keys || {})
      when :gocardless
        configuration[:provider_customer_id] = model.customer.gocardless_customer&.provider_customer_id
        configuration.merge!(model.customer.gocardless_customer&.settings&.symbolize_keys || {})
      when :cashfree
        configuration[:provider_customer_id] = model.customer.cashfree_customer&.provider_customer_id
        configuration.merge!(model.customer.cashfree_customer&.settings&.symbolize_keys || {})
      when :adyen
        configuration[:provider_customer_id] = model.customer.adyen_customer&.provider_customer_id
        configuration.merge!(model.customer.adyen_customer&.settings&.symbolize_keys || {})
      when :moneyhash
        configuration[:provider_customer_id] = model.customer.moneyhash_customer&.provider_customer_id
        configuration.merge!(model.customer.moneyhash_customer&.settings&.symbolize_keys || {})
      end

      configuration
    end

    def build_customer_metadata
      ::CollectionSerializer.new(
        model.customer.metadata,
        ::V1::Customers::MetadataSerializer,
        collection_name: "metadata"
      ).serialize[:metadata]
    end

    def subscriptions
      ::CollectionSerializer.new(
        model.subscriptions.includes([:customer, :plan]), ::V1::SubscriptionSerializer, collection_name: "subscriptions"
      ).serialize
    end

    def preview_subscriptions
      ::CollectionSerializer.new(
        model.subscriptions, ::V1::SubscriptionSerializer, collection_name: "subscriptions"
      ).serialize
    end

    def fees
      ::CollectionSerializer.new(
        model.fees.includes(
          [
            :true_up_fee,
            :subscription,
            :customer,
            :charge,
            :billable_metric,
            {charge_filter: {values: :billable_metric_filter}}
          ]
        ),
        ::V1::FeeSerializer,
        collection_name: "fees"
      ).serialize
    end

    def preview_fees
      ::CollectionSerializer.new(
        model.fees, ::V1::FeeSerializer, collection_name: "fees"
      ).serialize
    end

    def credits
      ::CollectionSerializer.new(model.credits, ::V1::CreditSerializer, collection_name: "credits").serialize
    end

    def metadata
      ::CollectionSerializer.new(
        model.metadata,
        ::V1::Invoices::MetadataSerializer,
        collection_name: "metadata"
      ).serialize
    end

    def applied_taxes
      ::CollectionSerializer.new(
        model.applied_taxes,
        ::V1::Invoices::AppliedTaxSerializer,
        collection_name: "applied_taxes"
      ).serialize
    end

    def error_details
      ::CollectionSerializer.new(
        model.error_details,
        ::V1::ErrorDetailSerializer,
        collection_name: "error_details"
      ).serialize
    end

    def applied_usage_thresholds
      ::CollectionSerializer.new(
        model.applied_usage_thresholds,
        ::V1::AppliedUsageThresholdSerializer,
        collection_name: "applied_usage_thresholds"
      ).serialize
    end

    def applied_invoice_custom_sections
      ::CollectionSerializer.new(
        model.applied_invoice_custom_sections,
        ::V1::Invoices::AppliedInvoiceCustomSectionSerializer,
        collection_name: "applied_invoice_custom_sections"
      ).serialize
    end

    def billing_periods
      ::CollectionSerializer.new(
        model.invoice_subscriptions,
        ::V1::Invoices::BillingPeriodSerializer,
        collection_name: "billing_periods"
      ).serialize
    end
  end
end
