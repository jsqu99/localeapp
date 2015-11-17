require 'fileutils'
# require 'rest-client'

###############
=begin
new_data
{
    "en" => {
        "foo" => {
            "bar" => {
                "jeff" => "hi jeff"
            }
        }
    }
}
locales = new_data.keys
=end


module Localeapp
  class Updater

    def update(data)
      puts "in updater#update: #{data}"
      return unless data.present?

      data['locales'].each do |short_code|
       if data['translations'] && data['translations'][short_code]
          next if short_code == "en"
          translations = { short_code => data['translations'][short_code] }
          Alchemy::Translations::EssenceBodyUpdater.new.update_bodies(translations)
        end
      end

      # now prune English out of the data as we don't respect english changes in lcoaleapp
      if data['translations'] && data['translations']['en']
        data['translations'].delete('en')
      end

      Alchemy::TranslationReceivedEmail.new.perform(data.to_json) unless empty_translations?(data)
    end

    def dump(data)
      data.each do |locale, translations|
        filename = File.join(Localeapp.configuration.translation_data_directory, "#{locale}.yml")
        atomic_write(filename) do |file|
          file.write generate_yaml({locale => translations})
        end
      end
    end

    private


    def empty_translations?(data)
      return true unless data['translations']

      data['translations'].each_value do |value|
        return false if value.present?
      end

      return true
    end

    def generate_yaml(translations)
      if defined?(Psych) && defined?(Psych::VERSION)
        Psych.dump(translations, :line_width => -1)[4..-1]
      else
        translations.ya2yaml[5..-1]
      end
    end

    def remove_flattened_key!(hash, locale, key)
      keys = I18n.normalize_keys(locale, key, '').map(&:to_s)
      current_key = keys.shift
      remove_child_keys!(hash[current_key], keys)
      hash
    end

    def remove_child_keys!(sub_hash, keys)
      return if sub_hash.nil?
      current_key = keys.shift
      if keys.empty?
        # delete key except if key is now used as a namespace for a child_hash
        unless sub_hash[current_key].is_a?(Hash)
          sub_hash.delete(current_key)
        end
      else
        child_hash = sub_hash[current_key]
        unless child_hash.nil?
          remove_child_keys!(child_hash, keys)
          if child_hash.empty?
            sub_hash.delete(current_key)
          end
        end
      end
    end

    # originally from ActiveSupport
    def atomic_write(file_name, temp_dir = Dir.tmpdir)
      target_dir = File.dirname(file_name)
      unless File.directory?(target_dir)
        raise "Could not write locale file, please make sure that #{target_dir} exists and is writable"
      end

      permissions = File.stat(file_name).mode if File.exist?(file_name)

      temp_file = Tempfile.new(File.basename(file_name), temp_dir)
      yield temp_file
      temp_file.close
      # heroku has /tmp on a different fs
      # so move first to sure they're on the same fs
      # so rename will work
      FileUtils.mv(temp_file.path, "#{file_name}.tmp")
      File.rename("#{file_name}.tmp", file_name)

      # chmod the file to its previous permissions
      # or set default permissions to 644
      File.chmod(permissions ? permissions : 0644 , file_name)
    end
  end
end
