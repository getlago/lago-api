# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    attr_reader :organization, :customer, :params

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

      create_params = params.slice(
        :auto_execute,
        :backdated_billing,
        :billing_items,
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

      quote = Quote.transaction do
        quote = organization.quotes.create!(
          customer:,
          **create_params
        )
        add_owners!(quote:, owners: params[:owners]) if params.has_key?(:owners)
        quote
      end

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
