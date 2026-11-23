
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

ice icebox icicle idle idea igloo image immigrate impala
ink inkwell insect inward iris island isle item ivy

jab jaguar jailjacket jam jar jersey jester jingle jolt journal jubilee
jasmine jelly jellybean jewel journey judge juice jungle

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

nab nail naive napkin navy nebula necklace needle nest net news nickel
night nightingale nimble noble nod nook nostril notebook nucleus numb nut

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

quack quaff quail quality quarry quart quarter quartz queen
queer quest quick quilt quinoa quirk quiver quorum

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

ukelele ulna umask umber umbrella uncle under unicorn
uniform union unique unit unity universe update upper
upright upset urban urge useful usual utter

valley vanilla vase vegetable velvet velvet violin
violet volcano volume

wagon walnut warehouse warrior waterfall waterway
wave weather web wedding whale wheat wheel
whistle willow window windmill winter wire wisdom
wizard wolf wonder wood wool world worm
writer

xenon xylophone

yacht yard yarn year yellow yogurt

zebra zero zipper zoo

agent algorithm attention bot byte chat chip
code context data debug embedding prompt token
vector neural model tensor llama kernel
robotics pixel matrix quantum
"""  # end of the base word list

# Issue #48: append a larger dictionary of easy, plain-English words so each
# generated API key has more entropy while staying simple to read and remember.
extra_words = """
badger beaver bobcat buffalo camel cheetah chipmunk cobra condor coyote ferret
gazelle gecko gopher heron hornet iguana jackal jellyfish jay koala lemur macaque
marlin meerkat mole mongoose newt oriole osprey penguin quokka rabbit raccoon rat
ray scorpion shark skunk spider stork swan tapir terrapin toucan vulture walrus
weasel wombat wren yak
amber beige black brown crimson cyan ebony ivory jade khaki lilac maroon navy
ochre pearl scarlet sepia teal white vermilion
aurora blizzard comet crater delta eclipse fog frost glacier gust hail haze
lagoon lava mist nebula ripple soil storm surf tide cove geyser desert dune
basil beet chive chili dill kale leek lentil mango pecan quinoa radish sage
sesame spinach squash thyme turnip yam date corn oat rice pea bean
awl blade bolt caliper chisel clamp drill gauge hatchet lathe level mallet
pliers pulley screw saw spool vise wrench nail nut hook rope ladder
blouse cape cloak denim shawl skirt veil boot hat glove scarf coat dress
shirt sock shoe vest
chime chord fanfare gong hum note pipe tone tune viola harp
brow calf chin foot forehead gum jaw joint rib shin skull spine toe
tongue vein nail ear nose cheek
run walk jump hop skip crawl climb swim fly drive sail row dig build write read
talk listen watch wait help find keep give take make feel want
big small long short tall wide deep light hard soft warm cool clean new old
slow fast bright loud quiet brave calm quick keen neat
attic barn cabin camp cellar church clover coast dairy dock farm forest grove
garden harbor hotel island market meadow office palace park port quay railway
ranch river road route shop stall street tunnel valley yard
anchor bell button candle chain clock compass cookie cup drawer hammer hook key
lock mailbox marble match needle notebook pencil pin plate pot rope spool
switch table thread token torch tower vase wheel whistle wrench
"""

# Order-preserving de-dup so sample() below can never return the same word twice,
# even if a word is listed more than once (the base list had a couple of repeats).
WORDS = list(dict.fromkeys(WORDS.split()))
WORDS.extend(w for w in extra_words.split() if w not in WORDS)
WORDS = [w for w in WORDS if w.isalpha()]

WORD_COUNT = 8


def generate_api_key():
    words = secrets.SystemRandom().sample(WORDS, WORD_COUNT)
    return "-".join(words)


if __name__ == "__main__":
    print(generate_api_key())
