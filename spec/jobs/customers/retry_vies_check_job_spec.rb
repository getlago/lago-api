# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RetryViesCheckJob, type: :job do
  let(:customer) { create(:customer, tax_identification_number: "IE6388047V") }
  let(:vies_response) do
    {
      country_code: "FR"
    }
  end

  before do
    customer.billing_entity.update(eu_tax_management: true, country: "FR")

    allow(Customers::EuAutoTaxesService).to receive(:call)
      .with(customer: customer, new_record: false, tax_attributes_changed: true)
      .and_call_original
    allow(Customers::ApplyTaxesService).to receive(:call)
      .and_call_original
    allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
  end

  it "calls the EuAutoTaxesService" do
    described_class.perform_now(customer.id)

    expect(Customers::EuAutoTaxesService).to have_received(:call)
  end

  context "when customer has no tax identification number" do
    let(:customer) { create(:customer, tax_identification_number: nil) }

    it "returns early" do
      described_class.perform_now(customer.id)

      expect(Customers::EuAutoTaxesService).not_to have_received(:call)
    end
  end

  context "when EuAutoTaxesService returns a tax code" do
    it "applies the tax code" do
      described_class.perform_now(customer.id)

      expect(Customers::ApplyTaxesService).to have_received(:call)
        .with(customer: customer, tax_codes: ["lago_eu_fr_standard"])
    end
  end

  describe "exponential retry configuration" do
    it "has correct retry options" do
      expect(described_class.sidekiq_options).to include("retry" => 5)
    end

    it "uses exponential backoff with maximum cap" do
      expect([30.seconds * (2**0), 1.hour].min).to eq(30.seconds)
      expect([30.seconds * (2**1), 1.hour].min).to eq(60.seconds)
      expect([30.seconds * (2**2), 1.hour].min).to eq(120.seconds)
      expect([30.seconds * (2**3), 1.hour].min).to eq(240.seconds)
      expect([30.seconds * (2**4), 1.hour].min).to eq(480.seconds)
      expect([30.seconds * (2**5), 1.hour].min).to eq(960.seconds)
      expect([30.seconds * (2**7), 1.hour].min).to eq(1.hour)
      expect([30.seconds * (2**10), 1.hour].min).to eq(1.hour)
    end

    it "has sidekiq_retry_in configured" do
      expect(described_class).to respond_to(:sidekiq_retry_in)
    end
  end
end
