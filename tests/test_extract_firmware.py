import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('extract_firmware', Path(__file__).resolve().parents[1] / 'extract_firmware.py')
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


class ContainerBounds(unittest.TestCase):
    def test_valid_and_out_of_range_payloads(self):
        name = 'firmware.bin'
        prefix = name.encode() + b'\0' + b'20260926000000'
        prefix += b'\0' * (-len(prefix) % 4)
        offset = len(prefix) + 8
        for declared_offset, size, valid in [(offset, 3, True), (offset, 4, False), (offset + 9, 3, False), (offset, 0, False)]:
            with self.subTest(offset=declared_offset, size=size), tempfile.TemporaryDirectory() as directory:
                data = prefix + struct.pack('<II', declared_offset, size) + b'abc'
                output = Path(directory) / name
                if valid:
                    extractor.extract_by_name(data, name, str(output))
                    self.assertEqual(output.read_bytes(), b'abc')
                else:
                    with self.assertRaises(RuntimeError):
                        extractor.extract_by_name(data, name, str(output))
                    self.assertFalse(output.exists())

    def test_truncated_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(RuntimeError):
                extractor.extract_by_name(b'firmware.bin\0', 'firmware.bin', str(Path(directory) / 'blob'))


if __name__ == '__main__':
    unittest.main()
