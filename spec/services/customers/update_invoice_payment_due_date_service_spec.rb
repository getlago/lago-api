# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateInvoicePaymentDueDateService, type: :service do
  subject(:update_service) { described_class.new(customer:, net_payment_term:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, net_payment_term: customer_net_payment_term) }
  let(:net_payment_term) { 30 }
  let(:customer_net_payment_term) { nil }

  describe '#call' do
    let(:draft_invoice) do
      create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse('21 Jun 2022'), net_payment_term: customer.applicable_net_payment_term, organization:)
    end

    before do
      draft_invoice
    end

    it 'updates invoice payment_due_date' do
      expect { update_service.call }.to change { draft_invoice.reload.payment_due_date }
        .from(DateTime.parse('21 Jun 2022'))
        .to(DateTime.parse('21 Jun 2022') + net_payment_term.days)
    end

    context "when the customer already has the same net_payment_term and the new value is nil" do
      let(:customer_net_payment_term) { 20 }
      let(:net_payment_term) { nil }

      before do
        organization.update(net_payment_term: 15)
      end

      it "sets the payment_due_date of the draft_invoice to the org level value" do
        expect { update_service.call }.to change { draft_invoice.reload.payment_due_date }
          .from(DateTime.parse('21 Jun 2022'))
          .to(DateTime.parse('21 Jun 2022') + organization.net_payment_term.days)
      end

      it "sets the net_payment_term of the draft_invoice to the org level value" do
        expect { update_service.call }.to change { draft_invoice.reload.net_payment_term }
          .from(customer_net_payment_term)
          .to(organization.net_payment_term)
      end
    end
  end
end
