# frozen_string_literal: true

require 'rails_helper'

describe Clock::EventsValidationJob, job: true, transaction: false do
  subject { described_class }

  describe '.perform' do
    let(:event) { create(:event) }

    before { event }

    it 'refresh the events materialized view' do
      # expect { described_class.perform_now }
      #  .to change(Events::LastHourMv, :count).by(1)
    end
  end
end
