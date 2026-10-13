# frozen_string_literal: true

require "rails_helper"
require "rake"

describe "organizations:delete_invoices_data" do # rubocop:disable RSpec/DescribeClass
  subject(:delete_invoices_data) { task.invoke(organization.id) }

  let(:task) { Rake::Task["organizations:delete_invoices_data"] }
  let(:organization) { create(:organization) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:invoice) { create(:invoice, organization:) }

  before do
    Rake.application.rake_require("tasks/organizations")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  context "with an x402 invoice payment" do
    before { create(:x402_settlement, :invoice_payment, x402_connection: connection, invoice:) }

    it { expect { delete_invoices_data }.to change(X402::Settlement, :count).from(1).to(0) }
  end

  context "with an x402 credit purchase granted through the invoice" do
    let(:wallet_transaction) { create(:wallet_transaction, organization:, invoice:) }
    let(:subscription) { create(:subscription, organization:) }

    before { create(:x402_settlement, x402_connection: connection, wallet_transaction:, subscription:) }

    it { expect { delete_invoices_data }.to change(X402::Settlement, :count).from(1).to(0) }
  end
end
