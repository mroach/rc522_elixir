# RC522

Driver for an RC522 RFID reader.

This currently barely works, but it works. Kinda. It's really bad. Sorry.

> If you are not embarrassed by the first version of your product, you've launched too late

### References:

* https://www.nxp.com/docs/en/data-sheet/MFRC522.pdf
* http://wg8.de/wg8n1496_17n3613_Ballot_FCD14443-3.pdf
* https://github.com/miguelbalboa/rfid
* https://github.com/pimylifeup/MFRC522-python/

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rc522` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rc522, "~> 0.1.0", github: "mroach/rc522_elixir"}
  ]
end
```
