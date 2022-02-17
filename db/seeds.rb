# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

user = User.find_or_initialize_by(email: 'gavin@hooli.com')
user.update(password: 'ILoveLago') unless user.password_digest.present?
orga = Organization.find_or_create_by(name: 'Hooli')
Membership.find_or_create_by(user: user, organization: orga, role: 'admin')
