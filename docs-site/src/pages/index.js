import React from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import styles from './index.module.css';

const RULES = [
  {
    title: 'Disclose agents',
    body: 'If an AI agent helped write the code, the PR and the commit trailer say so. Every change stays attributable. No hidden AI involvement.',
  },
  {
    title: 'Humans own the merges',
    body: 'Agents review and recommend. A human approves and merges. Nothing merges automatically, ever.',
  },
  {
    title: 'Quality and security are gates',
    body: 'Not advisory on the things that matter. The intake gate fails hard. The security lens blocks on real findings.',
  },
];

const ACCESS = [
  {
    title: 'CI',
    body: 'The govern layer. The intake gate and the review pipeline run on every PR, whoever or whatever authored it. The only mandatory surface: wire nothing else and you still have the airlock.',
  },
  {
    title: 'The CLI',
    body: 'Install once, then run the same deterministic gates locally, scaffold a repo with asdd init, and read a project’s activity on the read-only asdd dashboard. A spec that passes locally passes on the PR, because it is the same code.',
  },
  {
    title: 'The Goose operate kit',
    body: 'A ready-to-run operate layer on unmodified Goose, for projects that want the working agents and not just the gates. Optional; the standard mandates no runtime.',
  },
];

function Hero() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={styles.hero}>
      <div className="container">
        <h1 className={styles.heroTitle}>{siteConfig.title}</h1>
        <p className={styles.heroTagline}>Agentic Spec-Driven Development</p>
        <p className={styles.heroLede}>
          A contribution pipeline for software projects built with AI agents. Drop it into any GitHub
          repo. It handles the parts that break when AI is involved: undisclosed authorship, unchecked
          security, agents that auto-merge things they should not.
        </p>
        <div className={styles.heroButtons}>
          <Link className="button button--primary button--lg" to="/docs">
            Get started
          </Link>
          <Link className="button button--secondary button--lg" to="/docs/guides/operate-goose">
            Run it with Goose
          </Link>
          <Link className="button button--link button--lg" href="https://github.com/OneHillAI/ASDD">
            GitHub
          </Link>
        </div>
        <pre className={styles.heroCode}>bash cli/init.sh --goose /path/to/your-repo</pre>
      </div>
    </header>
  );
}

function Rules() {
  return (
    <section className={styles.rules}>
      <div className="container">
        <div className="row">
          {RULES.map((r) => (
            <div className="col col--4" key={r.title}>
              <div className={styles.ruleCard}>
                <h3>{r.title}</h3>
                <p>{r.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Access() {
  return (
    <section className={styles.rules}>
      <div className="container">
        <h2 className="text--center">Three ways in</h2>
        <div className="row">
          {ACCESS.map((a) => (
            <div className="col col--4" key={a.title}>
              <div className={styles.ruleCard}>
                <h3>{a.title}</h3>
                <p>{a.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function BringYourOwn() {
  return (
    <section className={styles.closer}>
      <div className="container">
        <p>
          ASDD installs into the repository, not into a chat window, so the governance is identical for
          every tool that reaches it. Bring your own assistant (Claude, Goose, Cursor, Copilot, your own
          harness) and your own spec tool: <Link to="https://github.github.com/spec-kit/">Spec Kit</Link>,{' '}
          <Link to="https://github.com/Fission-AI/OpenSpec">OpenSpec</Link>, or plain files. ASDD requires
          that a spec exists and is checked, not that a particular tool produced it.
        </p>
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <Layout
      title="Agentic Spec-Driven Development"
      description="A governed contribution pipeline for software projects built with AI agents.">
      <Hero />
      <main>
        <Rules />
        <Access />
        <BringYourOwn />
        <section className={styles.closer}>
          <div className="container">
            <p>
              Stewarded by the <Link href="https://onehill.org">OneHill Foundation</Link>. Read{' '}
              <Link to="/docs/concepts/why-asdd">why it exists</Link>,{' '}
              <Link to="/docs/concepts/what-is-asdd">what it is</Link>, and{' '}
              <Link to="/docs/concepts/how-it-works">how it works</Link>.
            </p>
          </div>
        </section>
      </main>
    </Layout>
  );
}
