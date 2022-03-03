require "rails/all"
require "fileutils"
require "shellwords"

RAILS_REQUIREMENT = ">= 7.0.0"
REPO_LINK = "https://github.com/alec-c4/ks-rails-api.git"

def apply_template!
  assert_minimum_rails_version
  add_template_repository_to_source_path

  # setup vscode
  copy_file ".editorconfig", force: true
  directory ".vscode", force: true

  # setup .gitignore 
  copy_file ".gitignore", force: true

  # setup Makefile
  copy_file "Makefile", force: true

  # setup Gemfile
  template "Gemfile.tt", force: true

  # setup lefthook
  copy_file "lefthook.yml", force: true

  after_bundle do
    apply_app_changes
    show_post_install_message
  end
end

def apply_app_changes
  # setup generators
  copy_file "config/initializers/generators.rb", force: true
  copy_file "config/initializers/semantic_logger.rb", force: true

  # setup Procfile
  copy_file "Procfile.dev", force: true

  # setup main configuration

  copy_file "config/settings.yml", force: true

  generate "strong_migrations:install"

  generate "hypershield:install"

  inject_into_file "config/application.rb", after: /config\.generators\.system_tests = nil\n/ do
    <<-'RUBY'
  # use config file
  config.settings = config_for(:settings)
    RUBY
  end

  inject_into_file "config/environments/development.rb",
                   after: /config\.action_cable\.disable_request_forgery_protection = true\n/ do
    <<-'RUBY'
    # Bullet
    config.after_initialize do
      Bullet.enable = true
      Bullet.bullet_logger = true
      Bullet.rails_logger = true
      Bullet.raise = true
    end

    # Identity cache
    config.identity_cache_store = :mem_cache_store, "localhost", {
      expires_in: 6.hours.to_i, # in case of network errors when sending a cache invalidation
      failover: false # avoids more cache consistency issues
    }    
    RUBY
  end

  inject_into_file "config/environments/test.rb",
                   after: /config\.action_view\.annotate_rendered_view_with_filenames = true\n/ do
    <<-'RUBY'
    # Bullet
    config.after_initialize do
      Bullet.enable = true
      Bullet.bullet_logger = true
      Bullet.raise = true # raise an error if n+1 query occurs
    end
    RUBY
  end

  inject_into_file "config/environments/production.rb",
                   after: /config\.active_record\.dump_schema_after_migration = false\n/ do
    <<-'RUBY'
    # Identity cache
    config.identity_cache_store = :mem_cache_store, "localhost", {
      expires_in: 6.hours.to_i, # in case of network errors when sending a cache invalidation
      failover: false # avoids more cache consistency issues
    }        
    RUBY
  end

  gsub_file "config/environments/production.rb", /STDOUT/, "$stdout"

  run "cp config/environments/production.rb config/environments/staging.rb"

  # setup migrations

  generate "migration EnableUuidPsqlExtension"
  uuid_migration_file = (Dir["db/migrate/*_enable_uuid_psql_extension.rb"]).first
  copy_file "migrations/uuid.rb", uuid_migration_file, force: true

  # setup i18n
  copy_file "config/initializers/i18n.rb", force: true
  directory "config/locales", force: true
  copy_file "config/i18n-tasks.yml", force: true

  # setup application logic

  copy_file "app/controllers/system_controller.rb", force: true
  copy_file "bin/dev", force: true
  run "chmod +x bin/dev"
  directory "app/interactions", force: true
  directory "app/mailers", force: true
  copy_file "config/puma.rb", force: true
  copy_file "config/routes.rb", force: true
  copy_file "config/initializers/active_interaction.rb", force: true

  # setup specs
  generate "rspec:install"
  directory "spec", force: true
  copy_file ".rspec", force: true

  # setup hypershield gem
  generate "hypershield:install"

  # run linters
  run "i18n-tasks normalize"
  run "standardrb --fix"
end

def show_post_install_message
  say "\n
  #########################################################################################

  App successfully created!\n

  Next steps:
  1 - add creadentials as described in README.md
  2 - configure database connections
  3 - configure application options in config/settings.yml
  4 - run following command \n
  git init && git add . &&  git commit -am 'Initial import' && lefthook install \n
  
  #########################################################################################\n", :green
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def add_template_repository_to_source_path
  if __FILE__.match?(%r{\Ahttps?://})
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("kickstart-tmp"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      REPO_LINK,
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{kickstart/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def gemfile_requirement(name)
  @original_gemfile ||= IO.read("Gemfile")
  req = @original_gemfile[/gem\s+['"]#{name}['"]\s*(,[><~= \t\d.\w'"]*)?.*$/, 1]
  req && req.tr("'", %(")).strip.sub(/^,\s*"/, ', "')
end

run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"
apply_template!
