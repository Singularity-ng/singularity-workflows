# ex_pgflow Examples

This directory contains **optional** example implementations that demonstrate how to extend ex_pgflow for specific use cases.

**Important:** These are NOT part of the core library. The core library provides workflow orchestration via PostgreSQL + pgmq. These examples show additional infrastructure patterns you might want to implement in your application.

## Available Examples

### [Instance Registry](instance_registry/)

**What:** GenServer for tracking which ex_pgflow instances are running across your cluster.

**When to use:** Production deployments with multiple instances where you need centralized observability.

**Status:** ⚠️ Placeholder implementation - requires completion before use.

**Key Point:** Multi-instance coordination already works via pgmq! This only adds observability, not functionality.

---

## How To Use Examples

1. **Copy to your application** - Don't use examples directly from this directory
2. **Implement placeholders** - Most examples have TODO sections requiring your Repo/schema
3. **Add to your supervision tree** - Examples are typically GenServers or processes
4. **Configure as needed** - Check example README for configuration options

## Contributing Examples

Have a useful pattern built on ex_pgflow? Submit a PR with:

- [ ] Complete implementation (no placeholders)
- [ ] Comprehensive README explaining when/why to use it
- [ ] Clear statement that it's optional (not required for core functionality)
- [ ] Tests demonstrating usage

Examples should be **production-ready reference implementations**, not experimental code.

## Philosophy

ex_pgflow follows the **library** philosophy:

- ✅ Core library: Minimal, focused, no opinions on infrastructure
- ✅ Examples: Show best practices but don't force them
- ✅ Your app: Choose what you need, implement what you want

We provide the workflow engine. You provide the infrastructure choices.
