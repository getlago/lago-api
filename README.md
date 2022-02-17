# Lago API

## Local Environment Configuration

- Install [rbenv](https://github.com/rbenv/rbenv)
```shell
# Ubuntu
sudo apt install rbenv

# macOS
brew install rbenv
brew install libpq

rbenv init
# close and re-open your terminal
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-doctor | bash
rbenv install 3.0.1
rbenv global 3.0.1
```

- Install project dependencies
```shell
gem install bundler
bundle install
```
- Create a file named `config/master.key`, get the value for it into [1Password](https://start.1password.com/open/i?a=CV2K6WPYLZBXXGIKIUYUJOA3Z4&v=4k453pfxong4lipf3oookha7ei&i=kc2v2trpahmnzcl5k3krdl2z3y&h=my.1password.com)
```shell
touch ./config/master.key
```
- Copy the `.env.dist` to `.env`
```shell
cp .env.dist .env
```

- Start the database by running `docker-compose up db`
- Prepare the database and run migrations
```shell
rake db:setup
rake db:migrate
```

- Launch the server
```shell
rails s
```

## GraphQL

### Generate GraphQL Schema

- You need to regenerate the schema each time you change something about GraphQL, if you don't, it will make your specs fail.
```shell
$ rake graphql:schema:dump
```