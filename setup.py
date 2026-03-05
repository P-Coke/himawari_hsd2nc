from setuptools import setup
from setuptools.dist import Distribution


cmdclass = {}


class BinaryDistribution(Distribution):
    # Force non-pure wheel so Linux auditwheel can repair to manylinux tags.
    def has_ext_modules(self):
        return True


try:
    # Force platform wheel tags because we bundle native executables.
    from wheel.bdist_wheel import bdist_wheel as _bdist_wheel

    class bdist_wheel(_bdist_wheel):
        def finalize_options(self):
            super().finalize_options()
            self.root_is_pure = False

    cmdclass["bdist_wheel"] = bdist_wheel
except Exception:
    pass

setup(cmdclass=cmdclass, distclass=BinaryDistribution)
