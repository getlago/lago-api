namespace :signup do
  desc "This task seeds lago with an organisation & a user for on premise deployment"
  task seed_organization: :environment do
    if ENV['LAGO_CREATE_ORG'].present? && ENV['LAGO_CREATE_ORG'] == 'true'
      pp "starting seeding environment"
      if ENV['LAGO_ORG_USER_PASSWORD'].present? && ENV['LAGO_ORG_USER_EMAIL'].present? && ENV['LAGO_ORG_NAME'].present?
        user = User.create_with(password: ENV['LAGO_ORG_USER_PASSWORD'])
          .find_or_create_by!(email: ENV['LAGO_ORG_USER_EMAIL'])
        organization = Organization.find_or_create_by!(name: ENV['LAGO_ORG_NAME'])
        if ENV['LAGO_ORG_API_KEY'].present?
          organization.api_key = ENV['LAGO_ORG_API_KEY']
          organization.save!
          Membership.find_or_create_by!(user: user, organization: organization, role: :admin)
        else
          raise "Couldn't find LAGO_ORG_API_KEY in environement variables"
        end
      else
        raise "Couldn't find LAGO_ORG_USER_PASSWORD, LAGO_ORG_USER_EMAIL or LAGO_ORG_NAME in environement variables"
      end
      pp "ending seeding environment"
    end
  end
end
