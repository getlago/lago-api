# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commitment, type: :model do
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to have_many(:applied_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:taxes) }

  it { is_expected.to validate_numericality_of(:amount_cents) }

  describe 'validations' do
    subject(:commitment) { build(:commitment) }

    describe 'of commitment type uniqueness' do
      let(:errors) { commitment.errors }

      context 'when it is unique in scope of plan' do
        it 'does not add an error' do
          expect(errors.where(:commitment_type, :taken)).not_to be_present
        end
      end

      context 'when it not is unique in scope of plan' do
        subject(:commitment) do
          build(:commitment, plan:)
        end

        let(:plan) { create(:plan) }
        let(:errors) { commitment.errors }

        before do
          create(:commitment, plan:)
          commitment.valid?
        end

        it 'adds an error' do
          expect(errors.where(:commitment_type, :taken)).to be_present
        end
      end
    end
  end
end
