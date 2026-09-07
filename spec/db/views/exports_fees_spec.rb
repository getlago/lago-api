# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_fees view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }

  let(:finalized_invoice) { create(:invoice, status: :finalized, organization:, customer:) }
  let(:deleted_invoice) { create(:invoice, status: :deleted, organization:, customer:) }

  let!(:finalized_fee) { create(:fee, invoice: finalized_invoice, subscription:, organization:) }
  let!(:deleted_fee) { create(:fee, invoice: deleted_invoice, subscription:, organization:) }
  # Recurring non-invoiceable fees are persisted with no invoice; the LEFT JOIN must keep them.
  let!(:invoiceless_fee) { create(:fee, invoice: nil, subscription:, organization:) }

  let(:exported_fee_ids) do
    ActiveRecord::Base.connection.select_values("SELECT lago_id FROM exports_fees")
  end

  it "excludes fees on deleted invoices while keeping finalized and invoice-less fees" do
    expect(exported_fee_ids).to include(finalized_fee.id, invoiceless_fee.id)
    expect(exported_fee_ids).not_to include(deleted_fee.id)
  end
end
