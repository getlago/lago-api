# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::UpdateInvoicePaymentDueDateService, type: :service do
  subject(:update_service) { described_class.new(organization:, net_payment_term:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, net_payment_term: customer_net_payment_term) }
  let(:customer_net_payment_term) { nil }
  let(:net_payment_term) { 30 }

  describe '#call' do
    let(:draft_invoice) do
      create(:invoice, status: :draft, customer:, organization:, issuing_date: DateTime.parse('21 Jun 2022'))
    end

    before do
      draft_invoice
    end

    it 'updates invoice payment_due_date' do
      expect { update_service.call }.to change { draft_invoice.reload.payment_due_date }
        .from(DateTime.parse('21 Jun 2022'))
        .to(DateTime.parse('21 Jun 2022') + net_payment_term.days)
    end

    it 'updates invoice net_payment_date' do
      expect { update_service.call }.to change { draft_invoice.reload.net_payment_term }
        .from(0)
        .to(30)
    end

    context "when customer has their own net_payment_term" do
      let(:customer_net_payment_term) { 10 }

      it "doesn't update fields" do
        expect { update_service.call }.not_to change { draft_invoice.reload.payment_due_date }
        expect { update_service.call }.not_to change { draft_invoice.reload.net_payment_term }
      end
    end
  end
end
