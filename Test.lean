import YamlTest

def main : IO UInt32 := do
  testParserSuite
  testComposerSuite
  testSerdeSuite
  testStreamingSuite
  return 0
