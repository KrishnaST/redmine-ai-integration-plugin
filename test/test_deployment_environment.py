import importlib.util
from pathlib import Path
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]
SPECIFICATION = importlib.util.spec_from_file_location(
    "deployment_environment", PROJECT / "tools/deployment/with_service_environment.py"
)
ENVIRONMENT = importlib.util.module_from_spec(SPECIFICATION)
SPECIFICATION.loader.exec_module(ENVIRONMENT)


class DeploymentEnvironmentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (PROJECT / "tmp").mkdir(exist_ok=True)

    def parse(self, text):
        with tempfile.TemporaryDirectory(dir=PROJECT / "tmp") as directory:
            path = Path(directory) / "test.env"
            path.write_text(text, encoding="utf-8")
            return ENVIRONMENT.read_environment_file(path)

    def test_assignments_quotes_and_comments(self):
        values = self.parse('# comment\nRAILS_ENV=production\nTEST_VALUE="test only"\n')
        self.assertEqual(values, {"RAILS_ENV": "production", "TEST_VALUE": "test only"})

    def test_special_characters_are_literal(self):
        values = self.parse("TEST_VALUE='test$literal#value'\nOTHER=$(not-executed)\n")
        self.assertEqual(values["TEST_VALUE"], "test$literal#value")
        self.assertEqual(values["OTHER"], "$(not-executed)")

    def test_unsupported_assignment_is_rejected_without_its_content(self):
        with self.assertRaises(SystemExit) as raised:
            self.parse("TEST_VALUE=test only\n")
        self.assertNotIn("test only", str(raised.exception))

    def test_invalid_name_is_rejected(self):
        with self.assertRaises(SystemExit):
            self.parse("INVALID-NAME=value\n")


if __name__ == "__main__":
    unittest.main()
