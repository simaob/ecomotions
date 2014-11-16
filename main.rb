require 'yaml'
require 'twitter'
secrets = YAML.load(File.open('config/secrets.yml'))

client = Twitter::REST::Client.new do |config|
  config.consumer_key    = secrets['consumer_key']
  config.consumer_secret = secrets['consumer_secret']
  config.bearer_token    = secrets['bearer_token']
end

client.search('#stonehenge', result_type: 'recent', lang: 'en').take(3).each do |tweet|
  puts tweet.text
end
