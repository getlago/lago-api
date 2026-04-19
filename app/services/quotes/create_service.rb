# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    attr_reader :organization, :customer, :params

    Result = BaseResult[:quote]

    def initialize(organization:, customer:, params:)
      @organization = organization
      @customer = customer
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "organization") unless organization
      return result.not_found_failure!(resource: "customer") unless customer
      return result.forbidden_failure! unless organization.feature_flag_enabled?(:order_forms)

      create_params = params.slice(
        :auto_execute,
        :backdated_billing,
        :commercial_terms,
        :contacts,
        :content,
        :currency,
        :description,
        :execution_mode,
        :internal_notes,
        :legal_text,
        :metadata,
        :order_type
      )

      if params.key?(:billing_items)
        validation = Quotes::BillingItems::ValidateService.call(
          organization:,
          order_type: params[:order_type],
          billing_items: params[:billing_items]
        )
        return validation unless validation.success?

        create_params[:billing_items] = validation.billing_items
      end

      quote = Quote.transaction do
        quote = organization.quotes.create!(
          customer:,
          **create_params
        )
        add_owners!(quote:, owners: params[:owners]) if params.has_key?(:owners)
        quote
      end

      # TODO: SendWebhookJob.perform_after_commit("quote.created", quote)

      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def add_owners!(quote:, owners:)
      return if owners.blank?

      owners.uniq.each do |user_id|
        quote.quote_owners.create!(organization:, user_id:)
      end
    end
  end
end
