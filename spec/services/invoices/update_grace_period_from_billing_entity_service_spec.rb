# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateGracePeriodFromBillingEntityService do
  subject { described_class.new(invoice:, old_grace_period:) }

  let(:invoice) do
    create(:invoice, :draft, issuing_date:, payment_due_date:, applied_grace_period: 12)
  end

  let(:issuing_date) { Time.current + old_grace_period.days }
  let(:payment_due_date) { issuing_date }

  let(:old_grace_period) { 12 }
  let(:new_grace_period) { 1 }

  before do
    invoice.billing_entity.update! invoice_grace_period: new_grace_period
  end

  shared_examples "does not change invoice dates" do
    it "does not change the issuing_date" do
      expect { subject.call }.not_to change { invoice.reload.issuing_date }
    end

    it "does not change the applied_grace_period" do
      expect { subject.call }.not_to change { invoice.reload.applied_grace_period }
    end

    it "does not change the payment due date" do
      expect { subject.call }.not_to change { invoice.reload.payment_due_date }
    end
  end

  context "when customer has invoice_grace_period" do
    before do
      invoice.customer.update!(invoice_grace_period: 12)
    end

    it_behaves_like "does not change invoice dates"
  end

  context "when invoice is not draft" do
    before do
      invoice.finalized!
    end

    it_behaves_like "does not change invoice dates"
  end

  context "when new grace period is equal to the already applied one" do
    before do
      invoice.update applied_grace_period: new_grace_period
    end

    it_behaves_like "does not change invoice dates"
  end

  context "when going from 12 to 15 days" do
    let(:new_grace_period) { 15 }

    it "changes the issuing_date by 3 days" do
      expect { subject.call }.to change(invoice, :issuing_date).by(3)
    end

    it "changes the applied_grace_to 15" do
      expect { subject.call }.to change(invoice, :applied_grace_period).to(15)
    end

    it "changes the payment_due_date by 3 days" do
      expect { subject.call }.to change(invoice, :payment_due_date).by(3)
    end
  end

  context "when going from 12 to 9 days" do
    let(:new_grace_period) { 9 }

    it "changes the issuing_date by 3 days" do
      expect { subject.call }.to change(invoice, :issuing_date).by(-3)
    end

    it "changes the applied_grace_to 9" do
      expect { subject.call }.to change(invoice, :applied_grace_period).to(9)
    end

    it "changes the payment_due_date by 3 days" do
      expect { subject.call }.to change(invoice, :payment_due_date).by(-3)
    end
  end
end
