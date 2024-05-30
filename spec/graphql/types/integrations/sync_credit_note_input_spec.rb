# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::SyncCreditNoteInput do
  subject { described_class }

  it { is_expected.to accept_argument(:credit_note_id).of_type('ID!') }
end
