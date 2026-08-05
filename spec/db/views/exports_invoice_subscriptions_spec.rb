# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_invoice_subscriptions view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }

  let(:finalized_invoice) { create(:invoice, status: :finalized, organization:, customer:) }
  let(:deleted_invoice) { create(:invoice, status: :deleted, organization:, customer:) }

  let!(:kept) { create(:invoice_subscription, invoice: finalized_invoice, subscription:, organization:) }
  let!(:hidden) { create(:invoice_subscription, invoice: deleted_invoice, subscription:, organization:) }

  let(:exported_ids) do
    ActiveRecord::Base.connection.select_values("SELECT lago_id FROM exports_invoice_subscriptions")
  end

  it "excludes invoice_subscriptions on deleted invoices" do
    expect(exported_ids).to include(kept.id)
    expect(exported_ids).not_to include(hidden.id)
  end
end
