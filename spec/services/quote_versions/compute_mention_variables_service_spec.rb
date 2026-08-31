# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::ComputeMentionVariablesService do
  subject(:service) { described_class.new(quote_version:) }

  let_it_be(:organization) { create_default(:organization, name: "Lago") }
  let_it_be(:billing_entity) do
    create_default(
      :billing_entity,
      organization:,
      name: "Globex SARL",
      legal_name: "Globex SARL",
      tax_identification_number: "FR12345678901",
      email: "billing@globex.example",
      address_line1: "4 rue de la Paix",
      address_line2: nil,
      zipcode: "75002",
      city: "Paris",
      state: nil,
      country: "FR",
      net_payment_term: 30
    )
  end
  let(:customer_net_payment_term) { nil }
  let(:customer_document_locale) { nil }
  let(:customer) do
    create_default(
      :customer,
      organization:,
      billing_entity:,
      name: "Hooli",
      legal_name: "Hooli Inc",
      firstname: "Gavin",
      lastname: "Belson",
      email: "procurement@hooli.example",
      net_payment_term: customer_net_payment_term,
      document_locale: customer_document_locale
    )
  end
  let(:quote) { create(:quote, organization:, customer:) }
  let(:start_date) { Date.new(2026, 4, 1) }
  let(:end_date) { Date.new(2027, 4, 1) }
  let(:quote_version) do
    create(
      :quote_version,
      :with_subscription_creation_billing_items,
      quote:,
      organization:,
      currency: "EUR",
      plan_start_date: start_date&.iso8601,
      plan_end_date: end_date&.iso8601
    )
  end

  let(:raw_address) do
    {
      "address_line1" => "4 rue de la Paix",
      "address_line2" => nil,
      "locality" => "Paris",
      "postal_code" => "75002",
      "administrative_area" => nil,
      "country_code" => "FR"
    }
  end

  describe ".call" do
    let(:result) { service.call }
    let(:variables) { result.mention_variables }

    it "computes the raw, locale-independent mention variables dictionary" do
      expect(result).to be_success
      expect(variables).to include(
        "customer_name" => "Hooli Inc - Gavin Belson",
        "customer_email" => "procurement@hooli.example",
        "organization_name" => "Lago",
        "organization_logo" => organization.logo_url,
        "billing_entity_name" => "Globex SARL",
        "billing_entity_legal_name" => "Globex SARL",
        "billing_entity_address" => raw_address,
        "billing_entity_tax_id" => "FR12345678901",
        "billing_entity_email" => "billing@globex.example",
        "quote_number" => quote.number,
        "quote_version" => quote_version.version.to_s,
        "quote_currency" => "EUR",
        "commercial_terms_term_duration" => {"unit" => "years", "count" => 1},
        "commercial_terms_start_date" => "2026-04-01",
        "commercial_terms_payment_terms" => 30
      )
      expect(variables["quote_date"]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    context "when the version names its own billing entity" do
      let(:issuing_entity) do
        create(
          :billing_entity,
          organization:,
          name: "Globex Inc",
          legal_name: "Globex Incorporated",
          tax_identification_number: "US987654321",
          email: "billing@globex.us.example",
          address_line1: "1 Market Street",
          zipcode: "94105",
          city: "San Francisco",
          state: "CA",
          country: "US"
        )
      end
      let(:quote_version) do
        create(
          :quote_version,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          currency: "EUR",
          billing_entity: issuing_entity,
          plan_start_date: start_date&.iso8601,
          plan_end_date: end_date&.iso8601
        )
      end

      it "renders that entity rather than the customer's" do
        expect(variables).to include(
          "billing_entity_name" => "Globex Inc",
          "billing_entity_legal_name" => "Globex Incorporated",
          "billing_entity_tax_id" => "US987654321",
          "billing_entity_email" => "billing@globex.us.example"
        )
      end

      # The invoice derives its own term from Customer#applicable_net_payment_term, i.e. the
      # customer's entity, so the quote has to promise the same thing.
      it "keeps the payment term on the customer's own chain" do
        expect(variables["commercial_terms_payment_terms"]).to eq(30)
      end
    end

    context "when the customer overrides the net payment term" do
      let(:customer_net_payment_term) { 45 }

      it "uses the customer's payment term" do
        expect(variables["commercial_terms_payment_terms"]).to eq(45)
      end
    end

    context "when the customer document locale is French" do
      let(:customer_document_locale) { "fr" }

      it "still produces locale-independent raw values" do
        expect(variables).to include(
          "commercial_terms_term_duration" => {"unit" => "years", "count" => 1},
          "commercial_terms_start_date" => "2026-04-01",
          "commercial_terms_payment_terms" => 30,
          "billing_entity_address" => raw_address
        )
      end
    end

    context "when the term spans whole months" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2026, 4, 1) }

      it "reports the duration in months" do
        expect(variables["commercial_terms_term_duration"]).to eq({"unit" => "months", "count" => 3})
      end
    end

    context "when the term spans less than a month" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2026, 1, 15) }

      it "reports the duration in days" do
        expect(variables["commercial_terms_term_duration"]).to eq({"unit" => "days", "count" => 14})
      end
    end

    context "when the end date is missing" do
      let(:end_date) { nil }

      it "leaves the term duration blank" do
        expect(variables["commercial_terms_term_duration"]).to be_nil
      end
    end

    context "when the term ends on a shorter month-end" do
      let(:start_date) { Date.new(2026, 1, 31) }
      let(:end_date) { Date.new(2026, 2, 28) }

      it "rounds down to whole days rather than a month" do
        expect(variables["commercial_terms_term_duration"]).to eq({"unit" => "days", "count" => 28})
      end
    end

    context "when the term spans more than a year but not a whole multiple" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2027, 2, 1) }

      it "reports the total months rather than years plus months" do
        expect(variables["commercial_terms_term_duration"]).to eq({"unit" => "months", "count" => 13})
      end
    end

    context "when the quote carries several plans" do
      let(:quote_version) do
        create(
          :quote_version,
          quote:,
          organization:,
          currency: "EUR",
          billing_items: {
            "plans" => [
              {"id" => SecureRandom.uuid, "type" => "plan", "payload" => {"startDate" => "2026-03-01", "endDate" => "2027-06-01"}},
              {"id" => SecureRandom.uuid, "type" => "plan", "payload" => {"startDate" => "2026-01-01", "endDate" => "2027-01-01"}}
            ]
          }
        )
      end

      it "spans the earliest start and the latest end" do
        expect(variables).to include(
          "commercial_terms_start_date" => "2026-01-01",
          "commercial_terms_term_duration" => {"unit" => "months", "count" => 17}
        )
      end
    end

    context "when a plan carries a full datetime" do
      let(:quote_version) do
        create(
          :quote_version,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          currency: "EUR",
          plan_start_date: "2026-01-01T09:30:00Z",
          plan_end_date: "2027-01-01T09:30:00Z"
        )
      end

      it "reads it as a calendar date" do
        expect(variables).to include(
          "commercial_terms_start_date" => "2026-01-01",
          "commercial_terms_term_duration" => {"unit" => "years", "count" => 1}
        )
      end
    end

    context "when the quote amends a running subscription" do
      let(:subscription) do
        create(:subscription, organization:, customer:, subscription_at: Date.new(2026, 2, 1))
      end
      let(:quote) do
        create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
      end
      let(:quote_version) do
        create(
          :quote_version,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          currency: "EUR",
          plan_start_date: nil,
          plan_end_date: "2027-02-01"
        )
      end

      it "falls back to the anniversary date of the amended subscription" do
        expect(variables).to include(
          "commercial_terms_start_date" => "2026-02-01",
          "commercial_terms_term_duration" => {"unit" => "years", "count" => 1}
        )
      end

      # The plan change bills under the target's entity, so the signed document has to name it too.
      context "when the target subscription is bound to another entity" do
        let(:target_entity) do
          create(:billing_entity, organization:, name: "Globex Inc", legal_name: "Globex Incorporated")
        end
        let(:subscription) do
          create(
            :subscription,
            organization:,
            customer:,
            plan: create(:plan, organization:, amount_currency: "EUR"),
            subscription_at: Date.new(2026, 2, 1),
            billing_entity: target_entity
          )
        end

        it "renders the target's entity rather than the customer's" do
          expect(target_entity).not_to eq(customer.billing_entity)
          expect(variables).to include(
            "billing_entity_name" => "Globex Inc",
            "billing_entity_legal_name" => "Globex Incorporated"
          )
        end
      end

      context "when the plan carries its own start date" do
        let(:quote_version) do
          create(
            :quote_version,
            :with_subscription_creation_billing_items,
            quote:,
            organization:,
            currency: "EUR",
            plan_start_date: "2026-05-01",
            plan_end_date: "2027-02-01"
          )
        end

        it "uses it over the amended subscription" do
          expect(variables["commercial_terms_start_date"]).to eq("2026-05-01")
        end
      end
    end

    context "when the quote is a one_off deal" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
      let(:quote_version) do
        create(:quote_version, :with_one_off_billing_items, quote:, organization:, currency: "EUR")
      end

      it "leaves the commercial term blank" do
        expect(variables).to include(
          "commercial_terms_start_date" => nil,
          "commercial_terms_term_duration" => nil
        )
      end

      context "when the add-on carries a service period" do
        let(:quote_version) do
          create(
            :quote_version,
            :with_one_off_billing_items,
            quote:,
            organization:,
            currency: "EUR",
            add_on_from_datetime: "2026-04-01T00:00:00Z",
            add_on_to_datetime: "2027-04-01T00:00:00Z"
          )
        end

        it "derives the commercial term from it" do
          expect(variables).to include(
            "commercial_terms_start_date" => "2026-04-01",
            "commercial_terms_term_duration" => {"unit" => "years", "count" => 1}
          )
        end
      end

      context "when the quote carries several add-ons" do
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {
              "addOns" => [
                {"id" => SecureRandom.uuid, "type" => "add_on", "payload" => {"fromDatetime" => "2026-03-01T00:00:00Z", "toDatetime" => "2027-06-01T00:00:00Z"}},
                {"id" => SecureRandom.uuid, "type" => "add_on", "payload" => {"fromDatetime" => "2026-01-01T00:00:00Z", "toDatetime" => "2027-01-01T00:00:00Z"}}
              ]
            }
          )
        end

        it "spans the earliest start and the latest end" do
          expect(variables).to include(
            "commercial_terms_start_date" => "2026-01-01",
            "commercial_terms_term_duration" => {"unit" => "months", "count" => 17}
          )
        end
      end

      context "when an add-on overrides its service period" do
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {
              "addOns" => [
                {
                  "id" => SecureRandom.uuid,
                  "type" => "add_on",
                  "payload" => {"fromDatetime" => "2026-01-01T00:00:00Z", "toDatetime" => "2027-01-01T00:00:00Z"},
                  "overrides" => {"fromDatetime" => "2026-02-01T00:00:00Z", "toDatetime" => "2026-08-01T00:00:00Z"}
                }
              ]
            }
          )
        end

        it "reads the overridden period, the one the fee is billed for" do
          expect(variables).to include(
            "commercial_terms_start_date" => "2026-02-01",
            "commercial_terms_term_duration" => {"unit" => "months", "count" => 6}
          )
        end
      end
    end
  end
end
