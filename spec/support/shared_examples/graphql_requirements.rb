# frozen_string_literal: true

RSpec.shared_examples 'requires current user' do
  it 'requires a current user' do
    expect(described_class.ancestors).to include(AuthenticableApiUser)
  end
end

RSpec.shared_examples 'requires current organization' do
  it 'requires a current organization' do
    expect(described_class.ancestors).to include(RequiredOrganization)
  end
end

RSpec.shared_examples 'requires permission' do |permission|
  it "requires #{permission} permission" do
    expect(described_class::REQUIRED_PERMISSION).to eq(permission)
  end
end
