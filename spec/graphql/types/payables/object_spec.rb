# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Payables::Object do
    subject { described_class }

    it 'has the correct graphql name' do
      expect(subject.graphql_name).to eq('Payable')
    end

    it 'includes the correct possible types' do
      expect(subject.possible_types).to include(Types::Payments::Object, Types::PaymentRequests::Object)
    end

    describe '.resolve_type' do
      let(:payment) { create(:payment) }
      let(:payment_request) { create(:payment_request) }

      it 'returns Types::Payments::Object for Payment objects' do
        allow(payment).to receive(:class).and_return(Payment)
        expect(subject.resolve_type(payment, {})).to eq(Types::Payments::Object)
      end

      it 'returns Types::PaymentRequests::Object for PaymentRequest objects' do
        allow(payment_request).to receive(:class).and_return(PaymentRequest)
        expect(subject.resolve_type(payment_request, {})).to eq(Types::PaymentRequests::Object)
      end

      it 'raises an error for unexpected types' do
        unexpected_object = double('Unexpected')
        allow(unexpected_object).to receive(:class).and_return('Unexpected')
        expect { subject.resolve_type(unexpected_object, {}) }.to raise_error(RuntimeError, /Unexpected payable type/)
      end
    end
  end
