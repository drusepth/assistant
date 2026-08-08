import { Controller } from "@hotwired/stimulus"

// Client-side generation (PASSWORDS_PLAN §6): the password exists nowhere
// until the form is saved. Random mode is 20 chars from a full pool;
// passphrase mode is five diceware-style words plus a digit — what people
// accept for passwords they must occasionally type. The meter is an honest
// charset-size estimate, not zxcvbn.
const WORDS = ("acorn amber anchor apple aspen autumn badge bagel bamboo barn basil beacon berry birch bison " +
  "blaze bloom bluff border boulder bramble brass breeze brick bridge brook bucket burrow cabin cactus camp " +
  "canoe canyon carbon cedar chalk cherry chess cider cliff clover coast cobalt comet compass copper coral " +
  "cotton cove crane crater creek cricket crimson crystal daisy dawn delta denim desert drift dune eagle " +
  "ember fable falcon feather fern field fjord flame flint fog forest fossil fox frost galaxy garden gate " +
  "geyser ginger glacier glade goose granite grape grove hail harbor hawk hazel heron hill hollow honey " +
  "horizon iceberg iris island ivory jade jasper juniper kayak kelp kettle lagoon lake lantern larch laurel " +
  "lava lemon lichen lilac linen lotus lunar maple marble meadow mesa mint mirror moss moth mountain mule " +
  "nectar nickel north nutmeg oasis ocean olive onyx opal orchard osprey otter owl oyster palm parka pebble " +
  "pecan penguin peony pine pistachio plateau plum pond poppy prairie prism pumpkin quail quartz quill rain " +
  "raven reef ridge river robin rowan saffron sage salmon sand sapphire seal sedge shale shore silver slate " +
  "sleet smoke snow solar sparrow spruce squall steppe stone storm summit sunset swan sycamore taiga talon " +
  "tempest thicket thistle thunder tide timber topaz trail trout tulip tundra turnip valley vapor violet " +
  "walnut wave willow winter wolf wren zephyr zinc").split(" ")

export default class extends Controller {
  static targets = ["field", "meter", "symbols", "passphrase"]

  generate() {
    const value = this.passphraseTarget.checked ? this.#passphrase() : this.#random()
    this.fieldTarget.value = value
    this.fieldTarget.dispatchEvent(new Event("input"))
  }

  measure() {
    const password = this.fieldTarget.value
    if (!password) { this.meterTarget.textContent = ""; return }

    const bits = this.#entropyBits(password)
    const grade = bits >= 70 ? "strong" : bits >= 40 ? "okay" : "weak"
    this.meterTarget.textContent = `~${bits} bits — ${grade}`
  }

  #random() {
    const pool = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789" +
      (this.symbolsTarget.checked ? "!@#$%^&*-_=+?" : "")
    return Array.from(this.#randoms(20), n => pool[n % pool.length]).join("")
  }

  #passphrase() {
    const words = Array.from(this.#randoms(5), n => WORDS[n % WORDS.length])
    const digit = this.#randoms(1)[0] % 10
    return `${words.join("-")}-${digit}`
  }

  #randoms(count) {
    return crypto.getRandomValues(new Uint32Array(count))
  }

  #entropyBits(password) {
    let pool = 0
    if (/[a-z]/.test(password)) pool += 26
    if (/[A-Z]/.test(password)) pool += 26
    if (/\d/.test(password)) pool += 10
    if (/[^a-zA-Z\d]/.test(password)) pool += 33
    return Math.round(password.length * Math.log2(pool || 1))
  }
}
