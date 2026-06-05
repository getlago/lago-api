# frozen_string_literal: true

module QuoteVersions
  class ComputeMentionVariablesService < BaseService
    Result = BaseResult[:mention_variables]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      I18n.with_locale(locale) do
        result.mention_variables = {
          "customer_name" => customer.name,
          "customer_email" => customer.email,
          "organization_name" => organization.name,
          "organization_logo" => organization.logo_url,
          "billing_entity_name" => billing_entity&.name,
          "billing_entity_legal_name" => billing_entity&.legal_name,
          "billing_entity_address" => billing_entity_address,
          "billing_entity_tax_id" => billing_entity&.tax_identification_number,
          "billing_entity_email" => billing_entity&.email,
          "quote_number" => quote.number,
          "quote_date" => format_date(quote.created_at),
          "quote_version" => quote_version.version.to_s,
          "quote_currency" => quote_version.currency,
          "commercial_terms_term_duration" => term_duration,
          "commercial_terms_start_date" => format_date(quote_version.start_date),
          "commercial_terms_payment_terms" => payment_terms
        }
      end

      result
    end

    private

    attr_reader :quote_version

    delegate :quote, to: :quote_version
    delegate :customer, :organization, to: :quote
    delegate :billing_entity, to: :customer

    def locale
      @locale ||= customer.preferred_document_locale
    end

    def billing_entity_address
      return if billing_entity.nil?

      address = Addressing::Address.new(
        address_line1: billing_entity.address_line1.to_s,
        address_line2: billing_entity.address_line2.to_s,
        locality: billing_entity.city.to_s,
        postal_code: billing_entity.zipcode.to_s,
        administrative_area: billing_entity.state.to_s,
        country_code: billing_entity.country.to_s,
        locale: locale.to_s
      )

      Addressing::DefaultFormatter.new.format(address, locale: locale.to_s, html: false).presence
    end

    def payment_terms
      term = customer.applicable_net_payment_term
      return if term.blank?

      I18n.t("quote_version.mention_variables.payment_terms", count: term)
    end

    # Picks the largest whole unit between the two dates (years, then months, then
    # days). A 12-month span renders as "1 year".
    def term_duration
      start_date = quote_version.start_date
      end_date = quote_version.end_date
      return if start_date.blank? || end_date.blank?

      months = whole_months_between(start_date, end_date)

      if months < 1
        translate_term_duration(:days, (end_date - start_date).to_i)
      elsif (months % 12).zero?
        translate_term_duration(:years, months / 12)
      else
        translate_term_duration(:months, months)
      end
    end

    # Whole calendar months between two dates, rounding down a partial trailing month.
    def whole_months_between(from, to)
      months = (to.year * 12 + to.month) - (from.year * 12 + from.month)
      (to.day < from.day) ? months - 1 : months
    end

    def translate_term_duration(unit, count)
      I18n.t("quote_version.mention_variables.term_duration.#{unit}", count:)
    end

    # Datetimes are resolved in the customer timezone before extracting the date; the locale-aware
    # format is defined under `date.formats.default` for each supported locale.
    def format_date(value)
      return if value.blank?

      date = value.respond_to?(:in_time_zone) ? value.in_time_zone(customer.applicable_timezone).to_date : value
      I18n.l(date, format: :default)
    end
  end
end
