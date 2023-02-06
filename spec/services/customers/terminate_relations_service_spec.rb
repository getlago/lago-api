# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::TerminateRelationsService, type: :service do
  subject(:terminate_service) { described_class.new(customer:) }

  let(:customer) { create(:customer, :deleted) }

  context 'with an active subscription' do
    let(:subscription) { create(:active_subscription, customer:) }

    before { subscription }

    it 'terminates the subscription' do
      freeze_time do
        expect { terminate_service.call }
          .to change { subscription.reload.status }.from('active').to('terminated')
          .and change(subscription, :terminated_at).from(nil).to(Time.current)
      end
    end
  end

  context 'with a pending subscription' do
    let(:subscription) { create(:pending_subscription, customer:) }

    before { subscription }

    it 'cancels the subscription' do
      freeze_time do
        expect { terminate_service.call }
          .to change { subscription.reload.status }.from('pending').to('canceled')
          .and change(subscription, :canceled_at).from(nil).to(Time.current)
      end
    end
  end

  context 'with draft invoices' do
    let(:subscription) { create(:active_subscription, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      invoices.each do |invoice|
        create(:invoice_subscription, invoice:, subscription:)
      end
    end

    it 'finalizes draft invoices' do
      terminate_service.call

      invoices.each { |i| expect(i.reload).to be_finalized }
    end
  end

  context 'with an applied coupon' do
    let(:applied_coupon) { create(:applied_coupon, customer:) }

    before { applied_coupon }

    it 'terminates the applied coupon' do
      terminate_service.call

      expect(applied_coupon.reload).to be_terminated
    end
  end

  context 'with an active wallet' do
    let(:wallet) { create(:wallet, customer:) }

    before { wallet }

    it 'terminates the wallet' do
      terminate_service.call

      expect(wallet.reload).to be_terminated
    end
  end
end
