# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKeyMailer, type: :mailer do
  describe '#rotated' do
    let(:mail) { described_class.with(api_key:).rotated }
    let(:api_key) { create(:api_key) }
    let(:organization) { api_key.organization }

    describe 'subject' do
      subject { mail.subject }

      it { is_expected.to eq 'Your Lago API key has been rolled' }
    end

    describe 'recipients' do
      subject { mail.bcc }

      it { is_expected.to eq organization.admins.pluck(:email) }
    end

    describe 'body' do
      subject { mail.body.to_s }

      it "includes organization's name" do
        expect(subject).to include organization.name
      end
    end
  end
end
