namespace :signup do
  desc "This task seeds lago with an organisation & a user for on premise deployment"
  task seed_organization: :environment do
    if ENV['CREATE_ORG'].present? && ENV['CREATE_ORG'] == 'true'
      pp "starting seeding environment"
      if ENV['ORG_USER_PASSWORD'].present? && ENV['ORG_USER_EMAIL'].present? && ENV['ORG_NAME'].present?
        user = User.create_with(password: ENV['ORG_USER_PASSWORD'])
          .find_or_create_by(email: ENV['ORG_USER_EMAIL'])
        organization = Organization.find_or_create_by!(name: ENV['ORG_NAME'])
        if ENV['ORG_API_KEY'].present?
          organization.api_key = ENV['ORG_API_KEY']
          organization.save
          Membership.find_or_create_by!(user: user, organization: organization, role: :admin)
        else
          raise "Couldn't find ORG_API_KEY in environement variables"
        end
      else
        raise "Couldn't find ORG_USER_PASSWORD, ORG_USER_EMAIL or ORG_NAME in environement variables"
      end
      pp "ending seeding environment"
    end
  end
end
