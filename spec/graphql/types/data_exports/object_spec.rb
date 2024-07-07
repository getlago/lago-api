require 'rails_helper'

RSpec.describe Types::DataExports::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:status).of_type('StatusEnum!') }
end
