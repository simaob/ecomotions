require 'yaml'

secrets = YAML.load(File.open('config/secrets.yml'))

class CartoDBClient

  def initialize(config)
    @key = config['key']
  end

  def create_record(protected_area_name, bounding_box, body, url, created_at)
    is_geolocated = !bounding_box.nil?
    the_geom = if is_geolocated
      puts bounding_box.coordinates.inspect
      first_polygon = bounding_box.coordinates.first
      first_polygon << first_polygon.first # close the polygon
      bounding_box_wkt = first_polygon.map{ |c| "#{c.first} #{c.last}" }.join(', ')
      "ST_Centroid(ST_GeomFromText('POLYGON((#{bounding_box_wkt}))', 4326))"
    else
      nil
    end
    query = <<-SQL
      INSERT INTO ecomotions_ecohack_2014
      (
        the_geom, body, is_geolocated, protected_area_name, tweet_url, created_at
      )
      VALUES (
        #{the_geom},
        '#{body}',
        #{is_geolocated},
        '#{protected_area_name}',
        '#{url}',
        TO_DATE('#{created_at}', 'yyyy-mm-dd')
      )
    SQL
    query = query.split("\n").map(&:strip).join(" ")

    `curl --data \"api_key=#{@key}&q=#{query}\" http://carbon-tool.cartodb.com/api/v2/sql`
  end
end





require 'twitter'

twitter_client = Twitter::REST::Client.new do |config|
  config.consumer_key    = secrets['twitter']['consumer_key']
  config.consumer_secret = secrets['twitter']['consumer_secret']
  config.bearer_token    = secrets['twitter']['bearer_token']
end

cartodb_client = CartoDBClient.new(secrets['cartodb'])

twitter_client.search('#stonehenge', result_type: 'recent', lang: 'en').take(15).each do |tweet|
  bounding_box = tweet.place && tweet.place.bounding_box
  is_geolocated = !bounding_box.nil?
  cartodb_client.create_record(
    'Stonehenge',
    bounding_box,
    tweet.text,
    tweet.url,
    tweet.created_at
  ) if is_geolocated
end
