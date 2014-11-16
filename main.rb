require 'byebug'
require 'yaml'

secrets = YAML.load(File.open('config/secrets.yml'))

class CartoDBClient

  def initialize(config)
    @key = config['key']
  end

  def create_record(protected_area_name, bounding_box, body, url, politeness_score, problem, created_at)
    is_geolocated = !bounding_box.nil?
    the_geom = if is_geolocated
      puts bounding_box.coordinates.inspect
      first_polygon = bounding_box.coordinates.first
      first_polygon << first_polygon.first # close the polygon
      bounding_box_wkt = first_polygon.map{ |c| "#{c.first} #{c.last}" }.join(', ')
      "ST_Centroid(ST_GeomFromText('POLYGON((#{bounding_box_wkt}))', 4326))"
    else
      "ST_GeomFromText('POINT(-1.8262150 51.1788820)', 4326)"
    end
    query = <<-SQL
      INSERT INTO ecomotions_ecohack_2014
      (
        the_geom, body, is_geolocated, protected_area_name, tweet_url, politeness_score, problem, created_at
      )
      VALUES (
        #{the_geom},
        '#{body}',
        #{is_geolocated},
        '#{protected_area_name}',
        '#{url}',
        '#{politeness_score}',
        '#{problem}',
        TO_DATE('#{created_at}', 'yyyy-mm-dd')
      )
    SQL
    query = query.split("\n").map(&:strip).join(" ")

    `curl --data \"api_key=#{@key}&q=#{query}\" http://carbon-tool.cartodb.com/api/v2/sql`
  end
end

require 'httparty'

class PolitenessBarometer
  def evaluate_politeness text
    response = HTTParty.post("http://politeness.mpi-sws.org/score-politeness", :body => { text: text })
    JSON.parse(response.body)["label"]
  end
end

class ProblemClassifier
  def initialize
    @problem_keywords = YAML.load(File.open('data/problem_keywords.yml'))
  end

  def classify(text)
    problem_scores = @problem_keywords.map do |problem, keywords|
      problem_score = keywords.inject(0) do |result, element|
        result += 1 if text =~ /#{element}/
        result
      end
      [problem, problem_score]
    end
    top_problem, top_score = problem_scores.max{ |e| e.last }
    if top_score > 0
      top_problem
    else
      nil
    end
  end
end

require 'twitter'

twitter_client = Twitter::REST::Client.new do |config|
  config.consumer_key    = secrets['twitter']['consumer_key']
  config.consumer_secret = secrets['twitter']['consumer_secret']
  config.bearer_token    = secrets['twitter']['bearer_token']
end

cartodb_client = CartoDBClient.new(secrets['cartodb'])
barometer = PolitenessBarometer.new
problem_classifier = ProblemClassifier.new
search_term = 'stonehenge'

since_id = File.read('data/since_id').to_i

puts since_id.inspect

twitter_client.search("#{search_term} -rt", lang: 'en', since_id: since_id).each do |tweet|
  bounding_box = tweet.place && tweet.place.bounding_box
  is_geolocated = !bounding_box.nil?
  politeness_score = barometer.evaluate_politeness(tweet.text)
  cartodb_client.create_record(
    search_term,
    (is_geolocated ? bounding_box : nil),
    tweet.text,
    tweet.url,
    politeness_score,
    problem_classifier.classify(tweet.text),
    tweet.created_at
  )
  since_id = tweet.id if tweet.id > since_id
end

File.write('data/since_id', since_id)
