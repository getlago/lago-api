# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  subject(:organization) do
    described_class.new(
      name: 'PiedPiper',
      email: 'foo@bar.com',
      country: 'FR',
      invoice_footer: 'this is an invoice footer',
    )
  end

  describe 'Validations' do
    it 'is valid with valid attributes' do
      expect(organization).to be_valid
    end

    it 'is not valid without name' do
      organization.name = nil

      expect(organization).not_to be_valid
    end

    it 'is valid with valid http webhook url' do
      organization.webhook_url = 'http://foo.bar'

      expect(organization).to be_valid
    end

    it 'is valid with valid https webhook url' do
      organization.webhook_url = 'https://foo.bar'

      expect(organization).to be_valid
    end

    it 'is invalid with invalid webhook url' do
      organization.webhook_url = 'foobar'

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
        filename: 'logo',
      )

      expect(organization).to be_valid
    end

    it 'is invalid with too big logo' do
      organization.logo.attach(
        io: File.open(Rails.root.join('spec/factories/images/big_sized_logo.jpg')),
        content_type: 'image/jpeg',
        filename: 'logo',
      )

      expect(organization).not_to be_valid
    end

    it 'is invalid with unsupported logo content type' do
      organization.logo.attach(
        io: File.open(Rails.root.join('spec/factories/images/logo.gif')),
        content_type: 'image/gif',
        filename: 'logo',
      )

      expect(organization).not_to be_valid
    end

    it 'is invalid with invalid timezone' do
      organization.timezone = 'foo'

      expect(organization).not_to be_valid
    end
  end

  describe 'Callbacks' do
    it 'generates the api key' do
      organization.save!

      expect(organization.api_key).to be_present
    end
  end
end
