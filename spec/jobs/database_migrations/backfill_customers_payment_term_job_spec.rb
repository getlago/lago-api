# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillCustomersPaymentTermJob do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:inheriting_customer) { create(:customer, organization:) }
  let(:structured_customer) { create(:customer, organization:) }

  before do
    customer.update_columns(net_payment_term: 30, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations
    inheriting_customer.update_columns(net_payment_term: nil, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations
    structured_customer.update_columns(net_payment_term: 30, payment_term: {"term_type" => "day_of_month", "day_of_month" => 5, "month_offset" => 1}) # rubocop:disable Rails/SkipsModelValidations
  end

  it "builds a net term from the legacy days" do
    perform_job

    expect(customer.reload.payment_term).to eq("term_type" => "net", "days" => 30)
  end

  it "leaves customers without a legacy term inheriting" do
    perform_job

    expect(inheriting_customer.reload.payment_term).to be_nil
  end

  it "keeps structured terms that are already set" do
    perform_job

    expect(structured_customer.reload.payment_term).to eq("term_type" => "day_of_month", "day_of_month" => 5, "month_offset" => 1)
  end

  it "does not enqueue another batch when the walk is over" do
    expect { perform_job }.not_to have_enqueued_job(described_class)
  end

  context "when the customer is discarded" do
    before { customer.discard! }

    it "backfills it too" do
      perform_job

      expect(Customer.with_discarded.find(customer.id).payment_term).to eq("term_type" => "net", "days" => 30)
    end
  end

  context "when the batch is full" do
    before { stub_const("#{described_class}::BATCH_SIZE", 1) }

    it "chains to the next batch from the last id" do
      first_id = Customer.unscoped.order(:id).first.id

      expect { perform_job }.to have_enqueued_job(described_class).with(first_id)
    end
  end

  context "when customers are still missing their term after the walk" do
    it "reports instead of finishing silently" do
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(Customer.unscoped.order(:id).last.id)

      expect(Rails.logger).to have_received(:error).with(/still NULL/)
    end
  end
end
