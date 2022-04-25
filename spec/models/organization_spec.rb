# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  subject(:organization) { described_class.new(name: 'PiedPiper') }

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
  end

  describe 'Callbacks' do
    it 'generates the api key' do
      organization.save!

      expect(organization.api_key).to be_present
    end
  end
end
