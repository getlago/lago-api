# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customer, type: :model do
  subject(:customer) { create(:customer) }

  let(:organization) { create(:organization) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:integration_customers).dependent(:destroy) }
  it { is_expected.to have_one(:netsuite_customer) }

  describe 'validations' do
    subject(:customer) do
      described_class.new(organization:, external_id:)
    end

    let(:external_id) { SecureRandom.uuid }

    it 'validates the country' do
      expect(customer).to be_valid

      customer.country = 'fr'
      expect(customer).to be_valid

      customer.country = 'foo'
      expect(customer).not_to be_valid

      customer.country = ''
      expect(customer).not_to be_valid
    end

    it 'validates the language code' do
      customer.document_locale = nil
      expect(customer).to be_valid

      customer.document_locale = 'en'
      expect(customer).to be_valid

      customer.document_locale = 'foo'
      expect(customer).not_to be_valid

      customer.document_locale = ''
      expect(customer).not_to be_valid
    end

    it 'validates the timezone' do
      expect(customer).to be_valid

      customer.timezone = 'Europe/Paris'
      expect(customer).to be_valid

      customer.timezone = 'foo'
      expect(customer).not_to be_valid

      customer.timezone = 'America/Guadeloupe'
      expect(customer).not_to be_valid
    end
  end

  describe 'preferred_document_locale' do
    subject(:customer) do
      described_class.new(
        organization:,
        document_locale: 'en'
      )
    end

    it 'returns the customer document_locale' do
      expect(customer.preferred_document_locale).to eq(:en)
    end

    context 'when customer does not have a document_locale' do
      before do
        customer.document_locale = nil
        customer.organization.document_locale = 'fr'
      end

      it 'returns the organization document_locale' do
        expect(customer.preferred_document_locale).to eq(:fr)
      end
    end
  end

  describe '#editable?' do
    subject(:editable) { customer.editable? }

    context 'when customer has a wallet' do
      let(:customer) { wallet.customer }
      let(:wallet) { create(:wallet) }

      it 'returns false' do
        expect(editable).to eq(false)
      end
    end

    context 'when customer has a coupon applied' do
      let(:customer) { applied_coupon.customer }
      let(:applied_coupon) { create(:applied_coupon) }

      it 'returns false' do
        expect(editable).to eq(false)
      end
    end

    context 'when customer has an addon applied' do
      let(:customer) { applied_add_on.customer }
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns false' do
        expect(editable).to eq(false)
      end
    end

    context 'when customer has an invoice' do
      let(:customer) { invoice.customer }
      let(:invoice) { create(:invoice) }

      it 'returns false' do
        expect(editable).to eq(false)
      end
    end

    context 'when customer has a subscription' do
      let(:customer) { subscription.customer }
      let(:subscription) { create(:subscription) }

      it 'returns false' do
        expect(editable).to eq(false)
      end
    end

    context 'when customer has no record that prevents editing' do
      it 'returns true' do
        expect(editable).to eq(true)
      end
    end
  end

  describe '#provider_customer' do
    subject(:customer) { create(:customer, organization:, payment_provider:) }

    context 'when payment provider is stripe' do
      let(:payment_provider) { 'stripe' }
      let(:stripe_customer) { create(:stripe_customer, customer:) }

      before { stripe_customer }

      it 'returns the stripe provider customer object' do
        expect(customer.provider_customer).to eq(stripe_customer)
      end
    end

    context 'when payment provider is gocardless' do
      let(:payment_provider) { 'gocardless' }
      let(:gocardless_customer) { create(:gocardless_customer, customer:) }

      before { gocardless_customer }

      it 'returns the gocardless provider customer object' do
        expect(customer.provider_customer).to eq(gocardless_customer)
      end
    end
  end

  describe '#applicable_timezone' do
    subject(:customer) do
      described_class.new(organization:, timezone: 'Europe/Paris')
    end

    it 'returns the customer timezone' do
      expect(customer.applicable_timezone).to eq('Europe/Paris')
    end

    context 'when customer does not have a timezone' do
      let(:organization_timezone) { 'Europe/London' }

      before do
        customer.timezone = nil
        organization.timezone = organization_timezone
      end

      it 'returns the organization timezone' do
        expect(customer.applicable_timezone).to eq('Europe/London')
      end

      context 'when organization timezone is nil' do
        let(:organization_timezone) { nil }

        it 'returns the default timezone' do
          expect(customer.applicable_timezone).to eq('UTC')
        end
      end
    end
  end

  describe '#applicable_invoice_grace_period' do
    subject(:customer) do
      described_class.new(organization:, invoice_grace_period: 3)
    end

    it 'returns the customer invoice_grace_period' do
      expect(customer.applicable_invoice_grace_period).to eq(3)
    end

    context 'when customer does not have an invoice grace period' do
      let(:organization_invoice_grace_period) { 5 }

      before do
        customer.invoice_grace_period = nil
        organization.invoice_grace_period = organization_invoice_grace_period
      end

      it 'returns the organization invoice_grace_period' do
        expect(customer.applicable_invoice_grace_period).to eq(5)
      end

      context 'when organization invoice_grace_period is nil' do
        let(:organization_invoice_grace_period) { 0 }

        it 'returns the default invoice_grace_period' do
          expect(customer.applicable_invoice_grace_period).to eq(0)
        end
      end
    end
  end

  describe 'timezones' do
    subject(:customer) do
      build(
        :customer,
        organization:,
        timezone: 'Europe/Paris',
        created_at: DateTime.parse('2022-11-17 23:34:23')
      )
    end

    let(:organization) { create(:organization, timezone: 'America/Los_Angeles') }

    it 'has helper to get dates in timezones' do
      aggregate_failures do
        expect(customer.created_at.to_s).to eq('2022-11-17 23:34:23 UTC')
        expect(customer.created_at_in_customer_timezone.to_s).to eq('2022-11-18 00:34:23 +0100')
        expect(customer.created_at_in_organization_timezone.to_s).to eq('2022-11-17 15:34:23 -0800')
      end
    end
  end

  describe 'slug' do
    let(:organization) { create(:organization, name: 'LAGO') }

    let(:customer) do
      build(:customer, organization:)
    end

    it 'assigns a sequential id and a slug to a new customer' do
      customer.save
      organization_id_substring = organization.id.last(4).upcase

      aggregate_failures do
        expect(customer).to be_valid
        expect(customer.sequential_id).to eq(1)
        expect(customer.slug).to eq("LAG-#{organization_id_substring}-001")
      end
    end

    context 'with custom document_number_prefix' do
      let(:organization) { create(:organization, name: 'LAGO') }

      before do
        create(:customer, organization:, sequential_id: 5)
        organization.update!(document_number_prefix: 'ORG-55')
      end

      it 'assigns a sequential id and a slug to a new customer' do
        customer.save

        aggregate_failures do
          expect(customer).to be_valid
          expect(customer.sequential_id).to eq(6)
          expect(customer.slug).to eq('ORG-55-006')
        end
      end
    end
  end
end
