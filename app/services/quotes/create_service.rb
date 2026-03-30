# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    Result = BaseResult[:quote]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      customer = organization.customers.find_by(id: params[:customer_id])
      return result.not_found_failure!(resource: "customer") unless customer

      if params[:billing_items].present?
        return result unless Quotes::BillingItemsValidator.new(
          result,
          billing_items: params[:billing_items],
          order_type: params[:order_type]
        ).valid?
      end

      quote = Quote.new(
        organization:,
        customer:,
        order_type: params[:order_type],
        status: :draft,
        version: 1,
        currency: params[:currency],
        description: params[:description],
        content: params[:content],
        legal_text: params[:legal_text],
        internal_notes: params[:internal_notes],
        billing_items: params[:billing_items],
        commercial_terms: params[:commercial_terms],
        contacts: params[:contacts],
        metadata: params[:metadata],
        auto_execute: params[:auto_execute] || false,
        execution_mode: params[:execution_mode],
        backdated_billing: params[:backdated_billing],
        share_token: SecureRandom.hex(32)
      )
      build_owners(quote)
      result.quote = quote

      quote.save!

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :organization, :params

    def build_owners(quote)
      return unless params[:owner_ids].is_a?(Array)

      organization.users.where(id: params[:owner_ids]).map do |user|
        quote.quote_owners.build(user:, organization:)
      end
    end
  end
end
