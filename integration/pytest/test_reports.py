"""Intentional outcomes for real JUnit producer integration, not project failures."""
import os
import pytest

STAGE = os.environ['DELTA_STAGE']


def test_stable():
    assert 2 + 2 == 4


def test_new_failure():
    assert STAGE == 'baseline', 'new regression <api> & unicode 参数😀'


def test_fixed_failure():
    assert STAGE == 'candidate', 'fixed in the candidate'


def test_persistent_failure():
    assert False, 'persistent failure'


@pytest.mark.parametrize('value', ['ASCII', '参数😀'])
def test_parameters(value):
    assert not (STAGE == 'candidate' and value != 'ASCII')


@pytest.mark.skip(reason='intentional skip')
def test_skipped():
    pass


@pytest.mark.xfail(reason='known limitation', strict=True)
def test_expected_failure():
    assert False


@pytest.mark.xfail(reason='unexpected pass is informational', strict=False)
def test_unexpected_pass():
    pass


@pytest.fixture
def broken_setup():
    raise RuntimeError('fixture setup error')


def test_setup_error(broken_setup):
    pass
