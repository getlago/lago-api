# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_invoices_taxes view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:) }

  let(:finalized_invoice) { create(:invoice, status: :finalized, organization:, customer:) }
  let(:deleted_invoice) { create(:invoice, status: :deleted, organization:, customer:) }

  let!(:kept) { create(:invoice_applied_tax, invoice: finalized_invoice, tax:, organization:) }
  let!(:hidden) { create(:invoice_applied_tax, invoice: deleted_invoice, tax:, organization:) }

  let(:exported_ids) do
    ActiveRecord::Base.connection.select_values("SELECT lago_id FROM exports_invoices_taxes")
  end

  it "excludes invoices_taxes on deleted invoices" do
    expect(exported_ids).to include(kept.id)
    expect(exported_ids).not_to include(hidden.id)
  end
end
