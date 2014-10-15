require 'umlaut/routes'

# not sure why including openurl gem doesn't do the require, but it
# seems to need this. 
require 'openurl'
require 'bootstrap-sass'

module Umlaut
  class Engine < Rails::Engine
    engine_name "umlaut"

    ## Umlaut patches assets:precompile rake task to make non-digest-named
    # copies of files matching this config. LOGICAL names of assets. 
    # These can be dirglobs if desired. 
    #
    # See lib/tasks/umlaut_asset_compile.rake
    # 
    # umlaut_ui.js and spinner.gif prob should have been put under umlaut/
    # dir, but we didn't. 
    config.non_digest_named_assets = ["umlaut/*.js", "umlaut_ui.js", "spinner.gif"]
    
    # We need the update_html.js script to be available as it's own
    # JS file too, not just compiled into application.js, so we can
    # deliver it to external apps using it (JQuery Content Utility).
    # It will now be available from path /assets/umlaut/update_html.js
    # in production mode with precompiled assets, also in dev mode, 
    # whatevers.     
    initializer "#{engine_name}.asset_pipeline" do |app|
      app.config.assets.precompile << 'umlaut/update_html.js'
      app.config.assets.precompile << "umlaut_ui.js"
    end

    initializer "#{engine_name}.backtrace_cleaner" do |app|

      engine_root_regex = Regexp.escape (self.root.to_s + File::SEPARATOR)

      # Clean those ERB lines, we don't need the internal autogenerated
      # ERB method, what we do need (line number in ERB file) is already there
      Rails.backtrace_cleaner.add_filter do |line|
        line.sub /(\.erb:\d+)\:in.*$/, "\\1"
      end

      # Remove our own engine's path prefix, even if it's 
      # being used from a local path rather than the gem directory. 
      Rails.backtrace_cleaner.add_filter do |line|
        line.sub(/^#{engine_root_regex}/, "#{engine_name} ")
      end

      # This actually seemed not to be neccesary, and wasn't behaving right? Let's
      # try without it...
      #
      # Keep Umlaut's own stacktrace in the backtrace -- we have to remove Rails
      # silencers and re-add them how we want. 
      Rails.backtrace_cleaner.remove_silencers!

      # Silence what Rails silenced, UNLESS it looks like
      # it's from Umlaut engine
      Rails.backtrace_cleaner.add_silencer do |line|
        (line !~ Rails::BacktraceCleaner::APP_DIRS_PATTERN) &&
        (line !~ /^#{engine_root_regex}/  ) &&
        (line !~ /^#{engine_name} /)
      end
    end
    
    # Patch with fixed 'fair' version of ConnectionPool, see 
    # active_record_patch/connection_pool.rb
    #initializer("#{engine_name}.patch_connection_pool", :before => "active_record.initialize_database") do |app|
      load File.join(self.root, "active_record_patch", "connection_pool.rb")
    #end
  end
end
