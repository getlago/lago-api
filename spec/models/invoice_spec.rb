# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoice, type: :model do
  describe 'validate_date_bounds' do
    let(:invoice) do
      build(:invoice, from_date: Time.zone.now - 2.days, to_date: Time.zone.now)
    end

    it 'ensures from_date is before to_date' do
      expect(invoice).to be_valid
    end

    context 'when from_date is after to_date' do
      let(:invoice) do
        build(:invoice, from_date: Time.zone.now + 2.days, to_date: Time.zone.now)
      end

      it 'ensures from_date is before to_date' do
        expect(invoice).not_to be_valid
      end
    end
  end

  describe 'sequential_id' do
    let(:subscription) { create(:subscription) }

    let(:invoice) do
      build(
        :invoice,
        from_date: Time.zone.now - 2.days,
        to_date: Time.zone.now,
        subscription: subscription,
      )
    end

    it 'assigns a sequential id to a new invoice' do
      invoice.save

      aggregate_failures do
        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(1)
      end
    end

    context 'when sequential_id is present' do
      before { invoice.sequential_id = 3 }

      it 'does not replace the sequential_id' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(3)
        end
      end
    end

    context 'when invoice alrady exsits' do
      before do
        create(
          :invoice,
          from_date: Time.zone.now - 2.days,
          to_date: Time.zone.now,
          subscription: subscription,
          sequential_id: 5,
        )
      end

      it 'takes the next available id' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(6)
        end
      end
    end

    context 'with invoices on other organization' do
      before do
        create(
          :invoice,
          from_date: Time.zone.now - 2.days,
          to_date: Time.zone.now,
          sequential_id: 1,
        )
      end

      it 'scopes the sequence to the organization' do
        invoice.save

        aggregate_failures do
          expect(invoice).to be_valid
          expect(invoice.sequential_id).to eq(1)
        end
      end
    end
  end

  describe 'number' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { build(:invoice, subscription: subscription) }

    it 'generates the invoice number' do
      invoice.save
      organization_id_substring = organization.id.last(4).upcase

      expect(invoice.number).to eq("LAG-#{organization_id_substring}-001-001")
    end
  end

  describe 'charge_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { create(:invoice, subscription: subscription) }
    let(:fees) { create_list(:fee, 3, invoice: invoice) }

    it 'returns the charges amount' do
      expect(invoice.charge_amount.to_s).to eq('0.00')
    end
  end

  describe 'credit_amount' do
    let(:organization) { create(:organization, name: 'LAGO') }
    let(:customer) { create(:customer, organization: organization) }
    let(:subscription) { create(:subscription, organization: organization, customer: customer) }
    let(:invoice) { create(:invoice, subscription: subscription) }
    let(:credit) { create(:credit, invoice: invoice) }

    it 'returns the credits amount' do
      expect(invoice.credit_amount.to_s).to eq('0.00')
    end
  end
end
