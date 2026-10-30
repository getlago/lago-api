# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260819134021_backfill_payment_terms")

RSpec.describe BackfillPaymentTerms do
  subject(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:structured_billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:inheriting_customer) { create(:customer, organization:, billing_entity:) }
  let(:structured_customer) { create(:customer, organization:, billing_entity:) }

  before do
    billing_entity.update_columns(net_payment_term: 0, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations
    structured_billing_entity.update_columns(net_payment_term: 15, payment_term: {"term_type" => "end_of_month"}) # rubocop:disable Rails/SkipsModelValidations
    customer.update_columns(net_payment_term: 30, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations
    inheriting_customer.update_columns(net_payment_term: nil, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations
    structured_customer.update_columns(net_payment_term: 30, payment_term: {"term_type" => "day_of_month", "day_of_month" => 5, "month_offset" => 1}) # rubocop:disable Rails/SkipsModelValidations
  end

  it "builds a net term from the legacy days on customers and billing entities" do
    migrate

    expect(customer.reload.payment_term).to eq("term_type" => "net", "days" => 30)
    expect(billing_entity.reload.payment_term).to eq("term_type" => "net", "days" => 0)
  end

  it "leaves customers without a legacy term inheriting" do
    migrate

    expect(inheriting_customer.reload.payment_term).to be_nil
  end

  it "keeps structured terms that are already set" do
    migrate

    expect(structured_customer.reload.payment_term).to eq("term_type" => "day_of_month", "day_of_month" => 5, "month_offset" => 1)
    expect(structured_billing_entity.reload.payment_term).to eq("term_type" => "end_of_month")
  end
end
