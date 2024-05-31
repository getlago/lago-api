# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  subject(:organization) do
    described_class.new(
      name: 'PiedPiper',
      email: 'foo@bar.com',
      country: 'FR',
      invoice_footer: 'this is an invoice footer'
    )
  end

  it { is_expected.to have_many(:stripe_payment_providers) }
  it { is_expected.to have_many(:gocardless_payment_providers) }
  it { is_expected.to have_many(:adyen_payment_providers) }

  it { is_expected.to have_many(:webhook_endpoints) }
  it { is_expected.to have_many(:webhooks).through(:webhook_endpoints) }

  it { is_expected.to validate_inclusion_of(:default_currency).in_array(described_class.currency_list) }

  it_behaves_like 'paper_trail traceable'

  describe 'Validations' do
    it 'is valid with valid attributes' do
      expect(organization).to be_valid
    end

    it 'is not valid without name' do
      organization.name = nil

      expect(organization).not_to be_valid
    end

    it 'is invalid with invalid email' do
      organization.email = 'foo.bar'

      expect(organization).not_to be_valid
    end

    it 'is invalid with invalid country' do
      organization.country = 'ZWX'

      expect(organization).not_to be_valid

      organization.country = ''

      expect(organization).not_to be_valid
    end

    it 'validates the language code' do
      organization.document_locale = nil
      expect(organization).not_to be_valid

      organization.document_locale = 'en'
      expect(organization).to be_valid

      organization.document_locale = 'foo'
      expect(organization).not_to be_valid

      organization.document_locale = ''
      expect(organization).not_to be_valid
    end

    it 'is invalid with invalid invoice footer' do
      organization.invoice_footer = SecureRandom.alphanumeric(601)

      expect(organization).not_to be_valid
    end

    it 'is valid with logo' do
      organization.logo.attach(
        io: File.open(Rails.root.join('spec/factories/images/logo.png')),
        content_type: 'image/png',
        filename: 'logo'
      )

      expect(organization).to be_valid
    end

    it 'is invalid with too big logo' do
      organization.logo.attach(
        io: File.open(Rails.root.join('spec/factories/images/big_sized_logo.jpg')),
        content_type: 'image/jpeg',
        filename: 'logo'
      )

      expect(organization).not_to be_valid
    end

    it 'is invalid with unsupported logo content type' do
      organization.logo.attach(
        io: File.open(Rails.root.join('spec/factories/images/logo.gif')),
        content_type: 'image/gif',
        filename: 'logo'
      )

      expect(organization).not_to be_valid
    end

    it 'is invalid with invalid timezone' do
      organization.timezone = 'foo'

      expect(organization).not_to be_valid
    end

    it 'is valid with email_settings' do
      organization.email_settings = ['invoice.finalized', 'credit_note.created']

      expect(organization).to be_valid
    end

    it 'is invalid with non permitted email_settings value' do
      organization.email_settings = ['email.not_permitted']

      expect(organization).not_to be_valid
      expect(organization.errors.first.attribute).to eq(:email_settings)
      expect(organization.errors.first.type).to eq(:unsupported_value)
    end
  end

  describe 'Callbacks' do
    it 'generates the api key' do
      organization.save!

      expect(organization.api_key).to be_present
    end
  end
end
