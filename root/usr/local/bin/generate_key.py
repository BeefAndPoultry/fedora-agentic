
#!/usr/bin/env python3

import secrets

WORDS = """
acorn airplane airport almond anchor angel
animal ant apple apron arch arrow artist
ash attic autumn

backpack bacon badge bagel bakery balloon bamboo
banana banner barn basket beach beacon bean
bear beard bedroom bee beetle bell berry
bicycle bird biscuit blanket blossom blue blueberry
boat book bookshelf boot bottle bowl branch
bread breakfast breeze brick bridge broccoli brook
broom brush bubble bucket building bulb butterfly
button

cabin cactus cake calendar camera camp candle
candy canyon captain caramel carpet carrot castle
cat caterpillar cave cedar celery cellar chain
chair chalk cherry chestnut chicken chimney chocolate
circle circus city claw clay clock cloud
clover coast coconut coffee coin compass cookie
copper coral corner cottage cotton country cowboy
crab crane creek cricket crown crystal cucumber
cup curtain cushion

daisy dance danger dark dawn daylight diamond
dinner dinosaur dirt dog dolphin donkey door
doughnut dragon drawer dream dress drift drink
drum duck dune dust

eagle earth echo edge egg elbow emerald engine
evening evergreen eye

fabric face fairy family feather fence fern
field fig fin finger fire fireplace firefly
fish flag flame flashlight flower flute forest
fork fountain fox frame freedom friend frog
fruit

garden garlic gate gentle ginger giraffe glass
globe glove glow goat gold golden goose grape
grass gravel green grocery ground guitar

hammer hamster harbor harmony harvest hat hawk
hazel heart hedgehog hello helmet hill history
honey horizon horse hospital hotel house hummingbird
hurricane

ice idea igloo ink insect island ivy

jacket jam jar jasmine jelly jewel journey judge
juice jungle

kangaroo kettle key keyboard kidney kitten kite
kitchen kiwi knee knife knot

ladder lake lamp lantern laptop lavender lawn
leaf leather lemon leopard letter library lighthouse
lightning lily lime lion lipstick lizard llama
lock log lonely locket love lucky lunch

machine magnet mailbox marble market meadow meal
meat melon memory melody metal midnight milk
mint mirror mitten mitten mixture mobile monkey
moon morning mosquito mountain mouse movie muffin
mushroom music mustard

nail napkin necklace needle nest net news night
nightingale notebook nut

oak oatmeal ocean octopus office oil olive onion
orange orbit orchard organ ostrich otter oven owl
oxygen

paddle page paint painter palace panda paper
parade paradise park parrot parsley party peach
peanut pear pebble pencil pepper perfume person
pet phone piano picnic picture pie pigeon pillow
pilot pineapple planet plant plate plum pocket
poem pond popcorn poppy porch potato pottery
pouch prairie present pretzel prince princess printer
prism prize pumpkin puppy puzzle

quail quality quarter quartz queen quilt quiver

rabbit raccoon radio rainbow raincoat raisin rake
ranch raspberry raven recipe record red reef
remote rescue restaurant ribbon rice river road
robot rocket rock roller roof room rooster rose
rubber ruby ruler runner

saddle safari sailor salad salmon salt sandwich
sapphire satellite saucer sausage scale scarf school
science scissors scooter screen sea seashell season
seed shadow shampoo shark sheep shelf shell
sheriff shield ship shirt shoe shop shovel
shower shrimp sidewalk signal silver singer sink
skate sketch ski skillet sky sled sleep
slipper smile smoke snail snake snow snowflake
soap soccer sock soda sofa soft soldier
song sound soup south space spark sparrow spoon
spring squirrel stadium stamp star starfish starlight
station steam steel stone strawberry stream street
sugar suitcase summer sunflower sunshine sunset
sweater swing sword

table taco tail talent tambourine tank tap
tape target tea teacher teapot teddy telescope
temple tennis tent theater thermometer thief thunder
ticket tiger tile time toast tomato toolbox tooth
toothbrush torch tornado towel tower toy tractor
train treasure tree triangle trumpet tulip tunnel
turkey turtle twilight

umbrella uncle unicorn uniform universe update
valley vanilla vase vegetable velvet velvet violin
violet volcano volume

wagon walnut warehouse warrior waterfall waterway
wave weather web wedding whale wheat wheel
whistle willow window windmill winter wire wisdom
wizard wolf wonder wood wool world worm
writer

xylophone

yacht yard yarn year yellow yogurt

zebra zero zipper zoo

agent algorithm attention bot byte chat chip
code context data debug embedding prompt token
vector neural model tensor llama kernel
robotics pixel matrix quantum
""".split()

WORD_COUNT = 8


def generate_api_key():
    words = secrets.SystemRandom().sample(WORDS, WORD_COUNT)
    return "-".join(words)


if __name__ == "__main__":
    print(generate_api_key())
