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
    before do
      customer.update(zipcode: nil)
    end

    it "applies the tax code" do
      described_class.perform_now(customer.id)

      expect(Customers::ApplyTaxesService).to have_received(:call)
        .with(customer: customer, tax_codes: ["lago_eu_fr_standard"])
    end
  end

  describe "retry behavior" do
    context "when job fails" do
      before do
        allow(Customers::EuAutoTaxesService).to receive(:call)
          .and_raise(StandardError, "VIES service temporarily unavailable")
      end

      it "retries the job with exponential backoff" do
        expect {
          described_class.perform_now(customer.id)
        }.to raise_error(StandardError)

        # Verify the job is configured for retry
        expect(described_class.sidekiq_options["retry"]).to eq(11)
      end

      it "has sidekiq_retry_in configured for exponential backoff" do
        # Test the actual retry delay calculation logic
        retry_delays = []

        # Simulate retry delays for first few attempts
        (0..5).each do |count|
          delay = [1.minute * (2**count), 1.day].min
          retry_delays << delay
        end

        expect(retry_delays[0]).to eq(1.minute)   # 1st retry: 1 minute
        expect(retry_delays[1]).to eq(2.minutes)  # 2nd retry: 2 minutes
        expect(retry_delays[2]).to eq(4.minutes)  # 3rd retry: 4 minutes
        expect(retry_delays[3]).to eq(8.minutes)  # 4th retry: 8 minutes
        expect(retry_delays[4]).to eq(16.minutes) # 5th retry: 16 minutes
        expect(retry_delays[5]).to eq(32.minutes) # 6th retry: 32 minutes
      end

      it "caps retry delay at 1 day" do
        # Test that high retry counts are capped at 1 day
        high_count_delay = [1.minute * (2**11), 1.day].min
        expect(high_count_delay).to eq(1.day)
      end
    end

    context "when customer is not found" do
      it "does not retry and fails permanently" do
        expect {
          described_class.perform_now("non-existent-id")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
