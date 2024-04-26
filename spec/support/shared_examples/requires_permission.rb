# frozen_string_literal: true

RSpec.shared_examples 'requires permission' do |permission|
  it "requires #{permission} permission" do
    expect(described_class::REQUIRED_PERMISSION).to eq(permission)
  end
end
