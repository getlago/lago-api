# frozen_string_literal: true

require "rails_helper"

describe "Add customer-specific taxes" do
  let(:organization) { create(:organization, country: "FR", eu_tax_management: false, billing_entities: [create(:billing_entity, country: "FR")]) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 149_00) }

  let(:american_attributes) do
    {
      name: "John",
      country: "US",
      address_line1: "123 Main St",
      address_line2: "",
      state: "Colorado",
      city: "Denver",
      zipcode: "80095",
      currency: "USD"
    }
  end

  let(:french_attributes) do
    {
      name: "Jean",
      country: "FR",
      address_line1: "123 Avenue du General",
      address_line2: "",
      state: "",
      city: "Paris",
      zipcode: "75018",
      currency: "EUR"
    }
  end

  let(:italian_attributes) do
    {
      country: "IT",
      address_line1: "123 Via Marconi",
      address_line2: "",
      state: "",
      city: "Roma",
      zipcode: "00146",
      currency: "EUR"
    }
  end

  def enable_eu_tax_management!
    Organizations::UpdateService.call!(organization:, params: {eu_tax_management: true})
  end

  include_context "with webhook tracking"

  context "when customer are created after the feature was enabled" do
    it "create taxes" do
      enable_eu_tax_management!

      create_or_update_customer(american_attributes.merge(external_id: "user_usa_123"))
      expect(Customer.find_by(external_id: "user_usa_123").taxes.sole.code).to eq "lago_eu_tax_exempt"

      create_or_update_customer(french_attributes.merge(external_id: "user_fr_123"))
      expect(Customer.find_by(external_id: "user_fr_123").taxes.sole.code).to eq "lago_eu_fr_standard"

      create_or_update_customer(italian_attributes.merge(external_id: "user_it_123"))
      expect(Customer.find_by(external_id: "user_it_123").taxes.sole.code).to eq "lago_eu_it_standard"

      webhooks_sent.clear
      # Update customer to provide an INVALID EU VAT identifier
      # Nothing changes and no API call is made
      create_or_update_customer({external_id: "user_it_123", tax_identification_number: "IT123"})
      expect(Customer.find_by(external_id: "user_it_123").taxes.reload.sole.code).to eq "lago_eu_it_standard"
      expect(webhooks_sent.first { it["webhook_type"] == "customer.vies_check" }.dig("customer", "vies_check")).to eq({
        "valid" => false,
        "valid_format" => false
      })

      webhooks_sent.clear
      # Update customer to provide a valid EU VAT identifier
      # A call is made to VIES api, we mock the service rather than the HTTP call because it's a SOAP API
      # This customer now have 0% vat
      mock_vies_check!("IT12345678901")
      create_or_update_customer({external_id: "user_it_123", tax_identification_number: "IT12345678901"})
      expect(Customer.find_by(external_id: "user_it_123").taxes.reload.sole.code).to eq "lago_eu_reverse_charge"
      expect(webhooks_sent.first { it["webhook_type"] == "customer.vies_check" }.dig("customer", "vies_check")).to eq({
        "countryCode" => "IT",
        "vatNumber" => "IT12345678901"
      })

      mock_vies_check!("FR12345678901")
      create_or_update_customer({external_id: "user_fr_123", tax_identification_number: "FR12345678901"})
      expect(Customer.find_by(external_id: "user_fr_123").taxes.sole.code).to eq "lago_eu_reverse_charge"

      customer = Customer.find_by(external_id: "user_it_123")
      # If I had a custom tax for this Customer
      # It removes the automatic VAT
      create_tax({name: "Banking rates", code: "banking_rates", rate: 1.3})
      create_or_update_customer({external_id: customer.external_id, tax_codes: ["banking_rates"]})
      expect(customer.taxes.sole.code).to eq "banking_rates"

      # Make an invoice with this tax
      addon = create(:add_on, code: :test, organization:)
      create_one_off_invoice(customer, [addon], taxes: ["banking_rates"])
      expect(customer.invoices.sole.taxes.sole.code).to eq "banking_rates"

      # Then, remove the tax_identification_number for the customer
      # The custom tax is overridden by the default VAT of the country, even if an invoice used the previous taxes
      create_or_update_customer({external_id: customer.external_id, tax_identification_number: nil})
      expect(customer.taxes.sole.code).to eq "lago_eu_it_standard"
    end
  end

  context "when VIES returns an error" do
    let(:retry_job) { class_double(Customers::RetryViesCheckJob) }

    it "does not change taxes but send the webhook" do
      enable_eu_tax_management!

      create_or_update_customer(french_attributes.merge(external_id: "user_fr_123"))
      expect(Customer.find_by(external_id: "user_fr_123").taxes.sole.code).to eq "lago_eu_fr_standard"

      webhooks_sent.clear
      vat_number = "FR12345678901"
      allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
        .and_raise(::Valvat::RateLimitError.new("rate limit exceeded", Valvat::Lookup::VIES))

      allow(Customers::RetryViesCheckJob).to receive(:set).and_return retry_job
      allow(retry_job).to receive(:perform_later)

      create_or_update_customer({external_id: "user_fr_123", tax_identification_number: vat_number})

      expect(Customer.find_by(external_id: "user_fr_123").taxes.reload.sole.code).to eq "lago_eu_fr_standard"
      expect(webhooks_sent.first { it["webhook_type"] == "customer.vies_check" }.dig("customer", "vies_check")).to eq({
        "valid" => false,
        "valid_format" => true,
        "error" => "The VIES web service returned the error: rate limit exceeded"
      })
    end
  end

  context "when customer are created before the feature was enabled" do
    it "does not create taxes until the customer is updated" do
      create_or_update_customer(american_attributes.merge(external_id: "user_usa_123"))
      expect(Customer.find_by(external_id: "user_usa_123").taxes).to be_empty

      enable_eu_tax_management!
      expect(Customer.find_by(external_id: "user_usa_123").taxes).to be_empty

      create_or_update_customer({external_id: "user_usa_123", tax_identification_number: "US-111"}) # Not EU VAT
      expect(Customer.find_by(external_id: "user_usa_123").taxes.sole.code).to eq "lago_eu_tax_exempt"
    end
  end

  context "when customer changes country" do
    it "updates taxes" do
      enable_eu_tax_management!

      create_or_update_customer(french_attributes.merge({external_id: "user_moving"}))
      customer = Customer.find_by(external_id: "user_moving")
      expect(customer.reload.taxes.sole.code).to eq "lago_eu_fr_standard"

      create_or_update_customer({external_id: customer.external_id, country: "DE"})
      expect(customer.reload.taxes.sole.code).to eq "lago_eu_de_standard"
    end
  end

  context "when customer have an invoice with other taxes" do
    it "does not affect the customer taxes" do
      enable_eu_tax_management!

      create_or_update_customer(italian_attributes.merge(external_id: "user_it_123"))
      customer = Customer.find_by(external_id: "user_it_123")
      expect(customer.taxes.sole.code).to eq "lago_eu_it_standard"

      # Make an invoice with another tax
      create_tax({name: "Banking rates", code: "banking_rates", rate: 1.3})
      addon = create(:add_on, code: :test, organization:)
      create_one_off_invoice(customer, [addon], taxes: ["banking_rates"])
      expect(customer.invoices.sole.taxes.sole.code).to eq "banking_rates"

      # The customer tax is unaffected
      expect(customer.taxes.sole.code).to eq "lago_eu_it_standard"
    end
  end

  context "when organization has a default tax" do
    it "does not affect the customer taxes" do
      enable_eu_tax_management!
      organization.taxes.where(code: "lago_eu_fr_standard").update!(applied_to_organization: true)

      mock_vies_check!("IT12345678901")
      create_or_update_customer(italian_attributes.merge(
        external_id: "user_it_123", tax_identification_number: "IT12345678901"
      ))
      customer = Customer.find_by(external_id: "user_it_123")
      expect(customer.taxes.reload.sole.code).to eq "lago_eu_reverse_charge"

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_#{customer.external_id}",
        plan_code: plan.code
      })

      # The default organization tax is not applied
      expect(customer.invoices.sole.taxes.sole.code).to eq "lago_eu_reverse_charge"
    end
  end

  context "when charge has a dedicated tax" do
    it "does not affect the customer taxes" do
      enable_eu_tax_management!
      billable_metric = create(:billable_metric, organization:, field_name: "item_id")
      charge = create(:standard_charge, :pay_in_advance, billable_metric:, plan:)
      create(:charge_applied_tax, charge:, tax: Tax.find_by(code: "lago_eu_fr_standard"))

      mock_vies_check!("IT12345678901")
      create_or_update_customer(italian_attributes.merge(
        external_id: "user_it_123", tax_identification_number: "IT12345678901"
      ))
      customer = Customer.find_by(external_id: "user_it_123")
      expect(customer.taxes.reload.sole.code).to eq "lago_eu_reverse_charge"

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_#{customer.external_id}",
        plan_code: plan.code
      })
      expect(customer.invoices.sole.taxes.sole.code).to eq "lago_eu_reverse_charge"

      create_event({
        code: billable_metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: "sub_#{customer.external_id}"
      })

      # The Advance fee charge has the charge taxes even if the customer has a different tax
      advance_fee_invoice = customer.invoices.order(created_at: :desc).first
      expect(advance_fee_invoice.taxes.sole.code).to eq "lago_eu_fr_standard"
      expect(advance_fee_invoice.fees.charge.sole.taxes.sole.code).to eq "lago_eu_fr_standard"
      expect(customer.taxes.reload.sole.code).to eq "lago_eu_reverse_charge"
    end
  end
end
