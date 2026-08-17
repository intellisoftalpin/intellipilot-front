import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/docs/domain/doc_path.dart';

/// The client-side mirror of the server's path jail. The server is the
/// authority — these rules exist so the viewer can decide *before* navigating
/// whether a link stays inside the shared folder, and they must agree with
/// `crates/core/src/docs/path.rs` exactly.
void main() {
  group('resolveInJail', () {
    test('collapses dot segments and leading slashes', () {
      expect(resolveInJail('guides/./intro.md'), 'guides/intro.md');
      expect(resolveInJail('guides/sub/../intro.md'), 'guides/intro.md');
      expect(resolveInJail('/guides/intro.md'), 'guides/intro.md');
      expect(resolveInJail('guides//intro.md'), 'guides/intro.md');
      expect(resolveInJail(''), '');
    });

    /// The central property: an escape is refused, never clamped. Clamping
    /// would open a different document than the author linked to.
    test('refuses every path that climbs above the root', () {
      for (final bad in [
        '..',
        '../secret.md',
        '../../etc/passwd',
        'guides/../../secret.md',
        'a/b/c/../../../../x',
        './../x',
      ]) {
        expect(resolveInJail(bad), isNull, reason: '$bad should escape');
      }
      // Descending and coming back stays inside.
      expect(resolveInJail('guides/../intro.md'), 'intro.md');
    });

    test('refuses backslashes, which are a second separator', () {
      expect(resolveInJail(r'a\b'), isNull);
    });
  });

  group('resolveDocLink', () {
    DocLinkTarget link(String from, String href) => resolveDocLink(
      from: from,
      href: href,
      webUrl: 'https://github.com/acme/docs',
      branch: 'main',
      docPath: 'docs',
    );

    test('relative links resolve against the containing directory', () {
      expect(
        link('guides/intro.md', 'setup.md'),
        const DocInternalLink('guides/setup.md'),
      );
      expect(
        link('guides/intro.md', './setup.md'),
        const DocInternalLink('guides/setup.md'),
      );
      expect(
        link('guides/intro.md', '../api/ref.md'),
        const DocInternalLink('api/ref.md'),
      );
      expect(link('intro.md', 'other.md'), const DocInternalLink('other.md'));
    });

    test('a leading slash means the root of the shared folder', () {
      expect(
        link('guides/deep/intro.md', '/top.md'),
        const DocInternalLink('top.md'),
      );
    });

    test('a fragment is carried through, or stays on the page alone', () {
      expect(
        link('a.md', 'b.md#install'),
        const DocInternalLink('b.md', anchor: 'install'),
      );
      expect(link('a.md', '#install'), const DocAnchorLink('install'));
    });

    test('a query string is not part of a path in a git tree', () {
      expect(link('a.md', 'b.md?v=2'), const DocInternalLink('b.md'));
    });

    test('absolute URLs leave as they are', () {
      expect(
        link('a.md', 'https://example.com/x'),
        const DocExternalLink('https://example.com/x'),
      );
      expect(
        link('a.md', 'mailto:team@example.com'),
        const DocExternalLink('mailto:team@example.com'),
      );
    });

    /// A link above the shared folder is redirected to the source host — that
    /// content is deliberately not served here, and doing nothing would just
    /// look like a broken link.
    test('links above the shared folder redirect to the git host', () {
      final target = link('intro.md', '../internal/spec.md');
      expect(target, isA<DocExternalLink>());
      final external = target as DocExternalLink;
      expect(external.escapedJail, isTrue);
      // Resolved against the REPOSITORY root, so it lands on the real file.
      expect(
        external.url,
        'https://github.com/acme/docs/blob/main/internal/spec.md',
      );
    });

    test('a link above the repository root falls back to its home page', () {
      final target = resolveDocLink(
        from: 'intro.md',
        href: '../../../elsewhere.md',
        webUrl: 'https://github.com/acme/docs',
        branch: 'main',
        docPath: 'docs',
      );
      expect(
        target,
        const DocExternalLink(
          'https://github.com/acme/docs',
          escapedJail: true,
        ),
      );
    });

    test('without a web URL an escaping link is dead rather than wrong', () {
      final target = resolveDocLink(
        from: 'intro.md',
        href: '../secret.md',
        webUrl: '',
        branch: 'main',
        docPath: 'docs',
      );
      expect(target, const DocDeadLink('../secret.md'));
    });

    test('a trailing slash on the web URL does not double up', () {
      final target =
          resolveDocLink(
                from: 'intro.md',
                href: '../spec.md',
                webUrl: 'https://git.example.com/acme/docs/',
                branch: 'main',
                docPath: 'docs',
              )
              as DocExternalLink;
      expect(target.url, 'https://git.example.com/acme/docs/blob/main/spec.md');
    });

    test('an empty href is dead, not a link to the current page', () {
      expect(link('a.md', ''), const DocDeadLink(''));
      expect(link('a.md', '   '), const DocDeadLink('   '));
    });

    /// With no shared folder configured the whole repository is the jail, so
    /// nothing can climb out of it either.
    test('an empty doc path still bounds resolution at the repo root', () {
      final target = resolveDocLink(
        from: 'intro.md',
        href: '../x.md',
        webUrl: 'https://github.com/acme/docs',
        branch: 'main',
        docPath: '',
      );
      expect(
        target,
        const DocExternalLink(
          'https://github.com/acme/docs',
          escapedJail: true,
        ),
      );
    });
  });
}
